#include "pk_tls_rules.h"

#include <ctype.h>
#include <limits.h>
#include <stdint.h>
#include <strings.h>
#include <string.h>

static int pKTLSEquals(const unsigned char *value, size_t length, const char *literal) {
    size_t literal_length = strlen(literal);
    if (length != literal_length) return 0;
    for (size_t index = 0; index < length; index++)
        if (tolower(value[index]) != tolower((unsigned char)literal[index])) return 0;
    return 1;
}

static void PKTLSTrim(const unsigned char **value, size_t *length) {
    while (*length && (**value == ' ' || **value == '\t')) { (*value)++; (*length)--; }
    while (*length && ((*value)[*length - 1] == ' ' || (*value)[*length - 1] == '\t')) (*length)--;
}

static int PKTLSMediaType(const unsigned char *value, size_t length, const char *type) {
    size_t type_length = strlen(type);
    return length >= type_length && pKTLSEquals(value, type_length, type) &&
        (length == type_length || value[type_length] == ';');
}

int PKTLSHostAllowed(const char *host) {
    size_t length = host ? strlen(host) : 0;
    const char *suffix = ".pikabu.ru";
    size_t suffix_length = strlen(suffix);
    if (!length || length > 253 || host[0] == '.' || host[length - 1] == '.') return 0;
    for (size_t index = 0; index < length; index++) {
        unsigned char c = (unsigned char)host[index];
        if (!(isalnum(c) || c == '-' || c == '.')) return 0;
    }
    if (length == suffix_length - 1) return strncasecmp(host, suffix + 1, length) == 0;
    return length > suffix_length && strcasecmp(host + length - suffix_length, suffix) == 0;
}

int PKTLSParseHTTPHeaders(const unsigned char *data, size_t length, PKTLSHTTPHeaders *headers) {
    size_t end = 0;
    size_t line = 0;
    size_t scan_length;
    int seen_content_type = 0;
    if (!data || !headers || length < 16) return 0;
    scan_length = length < PKTLS_MAX_HEADER_BYTES ? length : PKTLS_MAX_HEADER_BYTES;
    memset(headers, 0, sizeof(*headers));
    while (end + 3 < scan_length && !(data[end] == '\r' && data[end + 1] == '\n' &&
                                 data[end + 2] == '\r' && data[end + 3] == '\n')) end++;
    if (end + 3 >= scan_length || end < 12 || memcmp(data, "HTTP/1.", 7) || data[8] != ' ' ||
        !isdigit(data[9]) || !isdigit(data[10]) || !isdigit(data[11])) return 0;
    headers->status = (data[9] - '0') * 100 + (data[10] - '0') * 10 + data[11] - '0';
    headers->header_length = end + 4;
    line = 0;
    while (line < end) {
        size_t line_end = line;
        while (line_end < end && !(data[line_end] == '\r' && data[line_end + 1] == '\n')) line_end++;
        if (line_end != end && (line_end + 1 >= end || data[line_end] != '\r' || data[line_end + 1] != '\n')) return 0;
        if (line != 0) {
            size_t colon = line;
            const unsigned char *value;
            size_t value_length;
            while (colon < line_end && data[colon] != ':') colon++;
            if (colon == line || colon == line_end || data[line] == ' ' || data[line] == '\t') return 0;
            value = data + colon + 1;
            value_length = line_end - colon - 1;
            PKTLSTrim(&value, &value_length);
            if (pKTLSEquals(data + line, colon - line, "content-length")) {
                size_t parsed = 0;
                if (headers->has_content_length || !value_length) return 0;
                for (size_t index = 0; index < value_length; index++) {
                    if (!isdigit(value[index]) || parsed > (SIZE_MAX - (value[index] - '0')) / 10) return 0;
                    parsed = parsed * 10 + value[index] - '0';
                }
                headers->has_content_length = 1;
                headers->content_length = parsed;
            } else if (pKTLSEquals(data + line, colon - line, "transfer-encoding")) {
                if (!pKTLSEquals(value, value_length, "chunked")) return 0;
                headers->chunked = 1;
            } else if (pKTLSEquals(data + line, colon - line, "content-encoding")) {
                if (!pKTLSEquals(value, value_length, "identity")) return 0;
            } else if (pKTLSEquals(data + line, colon - line, "content-type")) {
                if (seen_content_type++) return 0;
                headers->image_content_type = value_length >= 6 &&
                    tolower(value[0]) == 'i' && tolower(value[1]) == 'm' &&
                    tolower(value[2]) == 'a' && tolower(value[3]) == 'g' &&
                    tolower(value[4]) == 'e' && value[5] == '/';
                headers->video_content_type = PKTLSMediaType(value, value_length, "video/mp4");
                headers->json_content_type = PKTLSMediaType(value, value_length, "application/json");
            }
        }
        line = line_end + 2;
    }
    return !headers->chunked || !headers->has_content_length;
}

int PKTLSDecodeChunked(const unsigned char *input, size_t input_length,
                       unsigned char *output, size_t output_capacity, size_t *output_length) {
    size_t offset = 0;
    size_t written = 0;
    if (!input || !output || !output_length) return 0;
    while (offset < input_length) {
        size_t line_end = offset;
        size_t chunk = 0;
        size_t digits = 0;
        while (line_end + 1 < input_length && !(input[line_end] == '\r' && input[line_end + 1] == '\n')) line_end++;
        if (line_end + 1 >= input_length) return 0;
        for (size_t index = offset; index < line_end && input[index] != ';'; index++) {
            unsigned char c = input[index];
            unsigned value;
            if (c >= '0' && c <= '9') value = c - '0';
            else if (c >= 'a' && c <= 'f') value = c - 'a' + 10;
            else if (c >= 'A' && c <= 'F') value = c - 'A' + 10;
            else return 0;
            if (chunk > (SIZE_MAX - value) / 16) return 0;
            chunk = chunk * 16 + value;
            digits++;
        }
        if (!digits) return 0;
        offset = line_end + 2;
        if (!chunk) {
            while (offset + 1 < input_length) {
                if (input[offset] == '\r' && input[offset + 1] == '\n') { *output_length = written; return offset + 2 == input_length; }
                while (offset + 1 < input_length && !(input[offset] == '\r' && input[offset + 1] == '\n')) offset++;
                if (offset + 1 >= input_length) return 0;
                offset += 2;
            }
            return 0;
        }
        if (chunk > output_capacity - written || chunk > input_length - offset ||
            chunk + 2 > input_length - offset || input[offset + chunk] != '\r' || input[offset + chunk + 1] != '\n') return 0;
        memcpy(output + written, input + offset, chunk);
        written += chunk;
        offset += chunk + 2;
    }
    return 0;
}

enum {
    PKTLS_STATE_SIZE = 0,
    PKTLS_STATE_SIZE_EXTENSION,
    PKTLS_STATE_SIZE_LF,
    PKTLS_STATE_DATA,
    PKTLS_STATE_DATA_CR,
    PKTLS_STATE_DATA_LF,
    PKTLS_STATE_TRAILER,
    PKTLS_STATE_TRAILER_LF,
    PKTLS_STATE_END_LF,
    PKTLS_STATE_DONE,
    PKTLS_STATE_ERROR
};

void PKTLSChunkedInit(PKTLSChunked *decoder, size_t limit) {
    if (!decoder) return;
    memset(decoder, 0, sizeof(*decoder));
    decoder->state = PKTLS_STATE_SIZE;
    decoder->limit = limit;
}

static int PKTLSHexDigit(unsigned char c, unsigned *value) {
    if (c >= '0' && c <= '9') { *value = c - '0'; return 1; }
    if (c >= 'a' && c <= 'f') { *value = c - 'a' + 10; return 1; }
    if (c >= 'A' && c <= 'F') { *value = c - 'A' + 10; return 1; }
    return 0;
}

int PKTLSChunkedFeed(PKTLSChunked *decoder,
                     const unsigned char *input, size_t length, size_t *consumed,
                     unsigned char *out, size_t out_capacity, size_t *produced) {
    size_t taken = 0;
    size_t written = 0;
    if (consumed) *consumed = 0;
    if (produced) *produced = 0;
    if (!decoder || !consumed || !produced || (length && !input) || (out_capacity && !out)) return PKTLS_CHUNK_ERROR;
    if (decoder->state == PKTLS_STATE_ERROR) return PKTLS_CHUNK_ERROR;

    while (taken < length && decoder->state != PKTLS_STATE_DONE) {
        unsigned char c = input[taken];
        switch (decoder->state) {
        case PKTLS_STATE_SIZE: {
            unsigned value;
            if (PKTLSHexDigit(c, &value)) {
                if (++decoder->digits > PKTLS_MAX_CHUNK_DIGITS ||
                    decoder->chunk_remaining > (SIZE_MAX - value) / 16) { decoder->state = PKTLS_STATE_ERROR; break; }
                decoder->chunk_remaining = decoder->chunk_remaining * 16 + value;
                taken++;
                continue;
            }
            if (!decoder->digits) { decoder->state = PKTLS_STATE_ERROR; break; }
            /* a chunk extension carries no body */
            if (c == ';') { decoder->state = PKTLS_STATE_SIZE_EXTENSION; taken++; continue; }
            if (c == '\r') { decoder->state = PKTLS_STATE_SIZE_LF; taken++; continue; }
            decoder->state = PKTLS_STATE_ERROR;
            break;
        }
        case PKTLS_STATE_SIZE_EXTENSION:
            if (c == '\r') decoder->state = PKTLS_STATE_SIZE_LF;
            else if (c == '\n') { decoder->state = PKTLS_STATE_ERROR; break; }
            taken++;
            continue;
        case PKTLS_STATE_SIZE_LF:
            if (c != '\n') { decoder->state = PKTLS_STATE_ERROR; break; }
            taken++;
            decoder->digits = 0;
            decoder->state = decoder->chunk_remaining ? PKTLS_STATE_DATA : PKTLS_STATE_TRAILER;
            continue;
        case PKTLS_STATE_DATA: {
            size_t available = length - taken;
            size_t room = out_capacity - written;
            size_t step = decoder->chunk_remaining;
            if (step > available) step = available;
            if (step > room) step = room;
            if (!step) { *consumed = taken; *produced = written; return PKTLS_CHUNK_MORE; }
            /* limit - step wraps when one chunk is larger than the whole cap, so subtract on the produced side */
            if (decoder->produced > decoder->limit ||
                step > decoder->limit - decoder->produced) { decoder->state = PKTLS_STATE_ERROR; break; }
            memcpy(out + written, input + taken, step);
            written += step;
            taken += step;
            decoder->produced += step;
            decoder->chunk_remaining -= step;
            if (!decoder->chunk_remaining) decoder->state = PKTLS_STATE_DATA_CR;
            continue;
        }
        case PKTLS_STATE_DATA_CR:
            if (c != '\r') { decoder->state = PKTLS_STATE_ERROR; break; }
            taken++;
            decoder->state = PKTLS_STATE_DATA_LF;
            continue;
        case PKTLS_STATE_DATA_LF:
            if (c != '\n') { decoder->state = PKTLS_STATE_ERROR; break; }
            taken++;
            decoder->state = PKTLS_STATE_SIZE;
            continue;
        case PKTLS_STATE_TRAILER:
            if (++decoder->trailer_bytes > PKTLS_MAX_TRAILER_BYTES) { decoder->state = PKTLS_STATE_ERROR; break; }
            taken++;
            /* an immediate crlf ends the body, anything else is a trailer line */
            if (c == '\r') decoder->state = PKTLS_STATE_END_LF;
            else if (c == '\n') { decoder->state = PKTLS_STATE_ERROR; break; }
            else decoder->state = PKTLS_STATE_TRAILER_LF;
            continue;
        case PKTLS_STATE_TRAILER_LF:
            if (++decoder->trailer_bytes > PKTLS_MAX_TRAILER_BYTES) { decoder->state = PKTLS_STATE_ERROR; break; }
            taken++;
            if (c == '\n') decoder->state = PKTLS_STATE_TRAILER;
            continue;
        case PKTLS_STATE_END_LF:
            if (c != '\n') { decoder->state = PKTLS_STATE_ERROR; break; }
            taken++;
            decoder->state = PKTLS_STATE_DONE;
            continue;
        default:
            decoder->state = PKTLS_STATE_ERROR;
            break;
        }
        if (decoder->state == PKTLS_STATE_ERROR) {
            *consumed = taken;
            *produced = written;
            return PKTLS_CHUNK_ERROR;
        }
    }
    *consumed = taken;
    *produced = written;
    return decoder->state == PKTLS_STATE_DONE ? PKTLS_CHUNK_DONE : PKTLS_CHUNK_MORE;
}
