#include "pk_text.h"

#include <string.h>

/* an unknown entity shows as itself instead of eating the line */
static const struct {
    const char *name;
    const char *utf8;
} pk_named_entities[] = {
    { "amp",    "&" },
    { "lt",     "<" },
    { "gt",     ">" },
    { "quot",   "\"" },
    { "apos",   "'" },
    { "nbsp",   " " },
    { "mdash",  "-" },
    { "ndash",  "-" },
    { "minus",  "\xe2\x88\x92" },
    { "hellip", "\xe2\x80\xa6" },
    { "laquo",  "\xc2\xab" },
    { "raquo",  "\xc2\xbb" },
    { "ldquo",  "\xe2\x80\x9c" },
    { "rdquo",  "\xe2\x80\x9d" },
    { "bull",   "\xe2\x80\xa2" },
    { "deg",    "\xc2\xb0" },
    { "times",  "\xc3\x97" },
    { "middot", "\xc2\xb7" },
    { "rsquo",  "'" },
    { "lsquo",  "'" },
    { "copy",   "\xc2\xa9" },
    { "reg",    "\xc2\xae" },
    { "trade",  "\xe2\x84\xa2" },
    { "euro",   "\xe2\x82\xac" },
    { "ruble",  "\xe2\x82\xbd" }
};

#define PK_NAMED_ENTITY_COUNT (sizeof(pk_named_entities) / sizeof(pk_named_entities[0]))

/* keeps counting after the room runs out so the caller learns the full length and still gets a valid prefix */
typedef struct {
    char *out;
    size_t capacity;
    size_t written;
    int overflowed;
} pk_writer;

static void pk_writer_init(pk_writer *w, char *out, size_t capacity) {
    w->out = out;
    w->capacity = capacity;
    w->written = 0;
    w->overflowed = 0;
}

static void pk_writer_byte(pk_writer *w, char c) {
    if (w->capacity && w->written + 1 < w->capacity) w->out[w->written] = c;
    else w->overflowed = 1;
    w->written++;
}

static void pk_writer_bytes(pk_writer *w, const char *bytes, size_t length) {
    size_t index;
    for (index = 0; index < length; index++) pk_writer_byte(w, bytes[index]);
}

static pk_status pk_writer_finish(pk_writer *w, size_t *written) {
    if (w->capacity) w->out[w->written < w->capacity ? w->written : w->capacity - 1] = '\0';
    if (written) *written = w->written;
    return w->overflowed ? PK_ERR_TRUNCATED : PK_OK;
}

static int pk_is_space(char c) {
    return c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\f' || c == '\v';
}

static int pk_lower(int c) {
    return (c >= 'A' && c <= 'Z') ? c + 32 : c;
}

static int pk_equals_span_ci(const char *a, size_t a_length, const char *b, size_t b_length) {
    size_t index;
    if (a_length != b_length) return 0;
    for (index = 0; index < a_length; index++)
        if (pk_lower((unsigned char)a[index]) != pk_lower((unsigned char)b[index])) return 0;
    return 1;
}

static int pk_equals_ci(const char *a, size_t a_length, const char *b) {
    return pk_equals_span_ci(a, a_length, b, strlen(b));
}

static size_t pk_encode_utf8(unsigned long code, char *out) {
    if (code < 0x80) {
        out[0] = (char)code;
        return 1;
    }
    if (code < 0x800) {
        out[0] = (char)(0xC0 | (code >> 6));
        out[1] = (char)(0x80 | (code & 0x3F));
        return 2;
    }
    if (code < 0x10000) {
        out[0] = (char)(0xE0 | (code >> 12));
        out[1] = (char)(0x80 | ((code >> 6) & 0x3F));
        out[2] = (char)(0x80 | (code & 0x3F));
        return 3;
    }
    out[0] = (char)(0xF0 | (code >> 18));
    out[1] = (char)(0x80 | ((code >> 12) & 0x3F));
    out[2] = (char)(0x80 | ((code >> 6) & 0x3F));
    out[3] = (char)(0x80 | (code & 0x3F));
    return 4;
}

/* `consumed` covers the whole reference including the semicolon */
static int pk_read_entity(const char *in, size_t available,
                          char *buffer, size_t *produced, size_t *consumed) {
    size_t end = 1;
    size_t index;
    if (available < 3) return 0;
    while (end < available && end < 12 && in[end] != ';') end++;
    if (end >= available || in[end] != ';' || end == 1) return 0;

    if (in[1] == '#') {
        unsigned long code = 0;
        size_t digits = 0;
        int hex = (end > 2) && (in[2] == 'x' || in[2] == 'X');
        for (index = hex ? 3 : 2; index < end; index++) {
            int c = pk_lower((unsigned char)in[index]);
            unsigned value;
            if (c >= '0' && c <= '9') value = (unsigned)(c - '0');
            else if (hex && c >= 'a' && c <= 'f') value = (unsigned)(c - 'a' + 10);
            else return 0;
            if (code > (0x10FFFFul - value) / (hex ? 16u : 10u)) return 0;
            code = code * (hex ? 16u : 10u) + value;
            digits++;
        }
        /* surrogates and the word joiner carry no text and confuse the label */
        if (!digits || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) return 0;
        if (code == 0 || code == 0x2060 || code == 0xFEFF) {
            *produced = 0;
            *consumed = end + 1;
            return 1;
        }
        *produced = pk_encode_utf8(code, buffer);
        *consumed = end + 1;
        return 1;
    }

    for (index = 0; index < PK_NAMED_ENTITY_COUNT; index++) {
        size_t length;
        if (!pk_equals_ci(in + 1, end - 1, pk_named_entities[index].name)) continue;
        length = strlen(pk_named_entities[index].utf8);
        memcpy(buffer, pk_named_entities[index].utf8, length);
        *produced = length;
        *consumed = end + 1;
        return 1;
    }
    return 0;
}

pk_status pk_text_decode_entities(const char *in, size_t in_length,
                                  char *out, size_t capacity, size_t *written) {
    pk_writer writer;
    size_t index = 0;
    if (written) *written = 0;
    if (!in || in_length > PK_MAX_DOCUMENT_BYTES) return PK_ERR_TOO_LARGE;
    pk_writer_init(&writer, out, capacity);
    while (index < in_length) {
        char buffer[4];
        size_t produced = 0;
        size_t consumed = 0;
        if (in[index] == '&' && pk_read_entity(in + index, in_length - index, buffer, &produced, &consumed)) {
            pk_writer_bytes(&writer, buffer, produced);
            index += consumed;
            continue;
        }
        pk_writer_byte(&writer, in[index]);
        index++;
    }
    return pk_writer_finish(&writer, written);
}

static int pk_tag_breaks_line(const char *name, size_t length) {
    return pk_equals_ci(name, length, "p") || pk_equals_ci(name, length, "div") ||
           pk_equals_ci(name, length, "li") || pk_equals_ci(name, length, "tr") ||
           pk_equals_ci(name, length, "h1") || pk_equals_ci(name, length, "h2") ||
           pk_equals_ci(name, length, "h3") || pk_equals_ci(name, length, "blockquote");
}

static int pk_tag_hides_body(const char *name, size_t length) {
    return pk_equals_ci(name, length, "script") || pk_equals_ci(name, length, "style") ||
           pk_equals_ci(name, length, "noscript") || pk_equals_ci(name, length, "template");
}

/* an unterminated tag eats the rest, so a truncated page cannot leak raw markup into the text */
static size_t pk_skip_tag(const char *html, size_t length, size_t start,
                          const char **name, size_t *name_length, int *closing) {
    size_t index = start + 1;
    size_t name_start;
    char quote = 0;
    *closing = 0;
    *name = html + index;
    *name_length = 0;
    if (index < length && html[index] == '/') {
        *closing = 1;
        index++;
    }
    name_start = index;
    while (index < length && !pk_is_space(html[index]) && html[index] != '>' && html[index] != '/') index++;
    *name = html + name_start;
    *name_length = index - name_start;
    while (index < length) {
        char c = html[index];
        if (quote) {
            if (c == quote) quote = 0;
        } else if (c == '"' || c == '\'') {
            quote = c;
        } else if (c == '>') {
            return index + 1;
        }
        index++;
    }
    return length;
}

/* a '<' inside javascript is not a tag, so the body is scanned as bytes */
static size_t pk_skip_hidden_body(const char *html, size_t length, size_t from,
                                  const char *name, size_t name_length) {
    size_t scan = from;
    while (scan + name_length + 2 < length) {
        if (html[scan] == '<' && html[scan + 1] == '/' &&
            pk_equals_span_ci(html + scan + 2, name_length, name, name_length)) {
            char after = html[scan + 2 + name_length];
            if (after == '>' || pk_is_space(after)) {
                const char *close_name;
                size_t close_length;
                int closing;
                return pk_skip_tag(html, length, scan, &close_name, &close_length, &closing);
            }
        }
        scan++;
    }
    return length;
}

pk_status pk_text_plain(const char *html, size_t length,
                        char *out, size_t capacity, size_t *written) {
    pk_writer writer;
    size_t index = 0;
    /* whitespace is emitted only when something printable follows, which trims and collapses in one pass */
    int pending_space = 0;
    int pending_newlines = 0;
    int produced_any = 0;
    if (written) *written = 0;
    if (!html || length > PK_MAX_DOCUMENT_BYTES) return PK_ERR_TOO_LARGE;
    pk_writer_init(&writer, out, capacity);

    while (index < length) {
        char c = html[index];

        if (c == '<') {
            const char *name;
            size_t name_length;
            int closing;
            size_t next = pk_skip_tag(html, length, index, &name, &name_length, &closing);
            if (!closing && pk_tag_hides_body(name, name_length)) {
                index = pk_skip_hidden_body(html, length, next, name, name_length);
                pending_space = produced_any;
                continue;
            }
            if (pk_equals_ci(name, name_length, "br") ||
                (closing && pk_tag_breaks_line(name, name_length))) {
                if (produced_any) {
                    pending_newlines = pending_newlines < 2 ? pending_newlines + 1 : 2;
                    pending_space = 0;
                }
            } else if (produced_any) {
                pending_space = 1;
            }
            index = next;
            continue;
        }

        if (pk_is_space(c)) {
            if (produced_any) pending_space = 1;
            index++;
            continue;
        }

        {
            char buffer[4];
            size_t produced = 0;
            size_t consumed = 0;
            if (c == '&' && pk_read_entity(html + index, length - index, buffer, &produced, &consumed)) {
                index += consumed;
                if (!produced) continue;
                /* an entity may decode to a space */
                if (produced == 1 && pk_is_space(buffer[0])) {
                    if (produced_any) pending_space = 1;
                    continue;
                }
                if (pending_newlines) { while (pending_newlines--) pk_writer_byte(&writer, '\n'); pending_newlines = 0; }
                else if (pending_space) pk_writer_byte(&writer, ' ');
                pending_space = 0;
                pk_writer_bytes(&writer, buffer, produced);
                produced_any = 1;
                continue;
            }
        }

        if (pending_newlines) { while (pending_newlines--) pk_writer_byte(&writer, '\n'); pending_newlines = 0; }
        else if (pending_space) pk_writer_byte(&writer, ' ');
        pending_space = 0;
        pk_writer_byte(&writer, c);
        produced_any = 1;
        index++;
    }
    return pk_writer_finish(&writer, written);
}

static int pk_scale_suffix(const char *text, size_t length, size_t index, long *scale, size_t *consumed) {
    unsigned char c = (unsigned char)text[index];
    if (c == 'k' || c == 'K') { *scale = 1000; *consumed = 1; return 1; }
    if (c == 'm' || c == 'M') { *scale = 1000000; *consumed = 1; return 1; }
    if (c == 0xD0 && index + 1 < length) {
        unsigned char next = (unsigned char)text[index + 1];
        if (next == 0xBA || next == 0x9A) { *scale = 1000; *consumed = 2; return 1; }     /* к К */
        if (next == 0xBC || next == 0x9C) { *scale = 1000000; *consumed = 2; return 1; }  /* м М */
    }
    return 0;
}

pk_status pk_number_compact(const char *text, size_t length, long *value) {
    size_t index = 0;
    long whole = 0;
    long fraction = 0;
    long fraction_scale = 1;
    long scale = 1;
    int negative = 0;
    int digits = 0;
    int seen_separator = 0;
    if (value) *value = 0;
    if (!text || !value || !length || length > 64) return PK_ERR_INVALID;

    while (index < length && pk_is_space(text[index])) index++;
    if (index < length && (text[index] == '-' || text[index] == '+')) {
        negative = text[index] == '-';
        index++;
    } else if (index + 2 < length && (unsigned char)text[index] == 0xE2 &&
               (unsigned char)text[index + 1] == 0x88 && (unsigned char)text[index + 2] == 0x92) {
        /* u+2212 is the minus the rating block renders */
        negative = 1;
        index += 3;
    }

    for (; index < length; index++) {
        char c = text[index];
        if (c >= '0' && c <= '9') {
            if (seen_separator) {
                if (fraction_scale <= 100) { fraction = fraction * 10 + (c - '0'); fraction_scale *= 10; }
            } else {
                if (whole > (2000000000L - (c - '0')) / 10) return PK_ERR_INVALID;
                whole = whole * 10 + (c - '0');
            }
            digits++;
            continue;
        }
        if ((c == '.' || c == ',') && !seen_separator && digits) {
            seen_separator = 1;
            continue;
        }
        /* pikabu groups thousands with a space */
        if (c == ' ' && digits && !seen_separator &&
            index + 1 < length && text[index + 1] >= '0' && text[index + 1] <= '9') continue;
        break;
    }
    if (!digits) return PK_ERR_INVALID;

    while (index < length && pk_is_space(text[index])) index++;
    if (index < length) {
        size_t consumed = 0;
        if (!pk_scale_suffix(text, length, index, &scale, &consumed)) return PK_ERR_INVALID;
        index += consumed;
        while (index < length && pk_is_space(text[index])) index++;
        if (index != length) return PK_ERR_INVALID;
    } else if (seen_separator) {
        /* pikabu never renders "3.5" without a suffix */
        return PK_ERR_INVALID;
    }

    {
        long part = scale > 1 && fraction_scale > 1 ? fraction * scale / fraction_scale : 0;
        long result;
        if (whole > (2000000000L - part) / scale) return PK_ERR_INVALID;
        result = whole * scale + part;
        *value = negative ? -result : result;
    }
    return PK_OK;
}

int pk_rating_label(const char *text, size_t length, long *value) {
    long numbers[2] = {0, 0};
    size_t found = 0, index = 0;
    if (value) *value = 0;
    if (!text || !value || length > 1024) return 0;
    while (index < length && found < 2) {
        long number = 0;
        size_t digits = 0;
        while (index < length && (text[index] < '0' || text[index] > '9')) index++;
        while (index < length && text[index] >= '0' && text[index] <= '9') {
            if (number > 100000000L) return 0;
            number = number * 10 + (text[index++] - '0');
            digits++;
        }
        if (digits) numbers[found++] = number;
    }
    if (found != 2) return 0;
    *value = numbers[0] - numbers[1];
    return 1;
}

int pk_profile_rating(const char *text, size_t length, int *negative) {
    size_t index = 0;
    size_t digits = 0;
    unsigned long whole = 0;
    int sign = 0;
    if (negative) *negative = 0;
    if (!text || !negative || !length || length > 32) return 0;
    if (text[index] == '-') { sign = 1; index++; }
    while (index < length && text[index] >= '0' && text[index] <= '9') {
        unsigned int digit = (unsigned int)(text[index++] - '0');
        if (whole > (2000000000UL - digit) / 10) return 0;
        whole = whole * 10 + digit;
        digits++;
    }
    if (!digits) return 0;
    if (index < length && text[index] == '.') {
        size_t fraction = 0;
        index++;
        while (index < length && text[index] >= '0' && text[index] <= '9') { index++; fraction++; }
        if (!fraction || (whole == 2000000000UL && fraction)) return 0;
    }
    if (index != length) return 0;
    *negative = sign;
    return 1;
}

pk_status pk_number_format(long value, char *out, size_t capacity, size_t *written) {
    pk_writer writer;
    long absolute = value < 0 ? -value : value;
    if (written) *written = 0;
    pk_writer_init(&writer, out, capacity);
    if (value < 0) pk_writer_byte(&writer, '-');
    if (absolute < 1000) {
        char digits[12];
        size_t count = 0;
        if (!absolute) pk_writer_byte(&writer, '0');
        while (absolute) { digits[count++] = (char)('0' + absolute % 10); absolute /= 10; }
        while (count) pk_writer_byte(&writer, digits[--count]);
        return pk_writer_finish(&writer, written);
    }
    {
        long thousands = absolute / 1000;
        long tenths = (absolute % 1000) / 100;
        char digits[12];
        size_t count = 0;
        long scan = thousands;
        while (scan) { digits[count++] = (char)('0' + scan % 10); scan /= 10; }
        while (count) pk_writer_byte(&writer, digits[--count]);
        /* one decimal only while it fits in four characters */
        if (thousands < 10 && tenths) {
            pk_writer_byte(&writer, ',');
            pk_writer_byte(&writer, (char)('0' + tenths));
        }
        pk_writer_byte(&writer, 'k');
    }
    return pk_writer_finish(&writer, written);
}

int pk_text_is_count_label(const char *text, size_t length) {
    size_t index;
    int digits = 0;
    if (!text || !length) return 1;
    for (index = 0; index < length; index++) {
        char c = text[index];
        if (c >= '0' && c <= '9') { digits++; continue; }
        if (c == '.' || c == ',' || c == '+' || c == '-' || pk_is_space(c)) continue;
        {
            long scale;
            size_t consumed;
            if (pk_scale_suffix(text, length, index, &scale, &consumed)) { index += consumed - 1; continue; }
        }
        return 0;
    }
    return digits > 0;
}
