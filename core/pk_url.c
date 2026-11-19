#include "pk_url.h"

#include <string.h>

#include "pk_text.h"

static const char pk_url_default_host[] = "pikabu.ru";

static int pk_url_lower(int c) {
    return (c >= 'A' && c <= 'Z') ? c + 32 : c;
}

static int pk_url_prefix_ci(const char *value, size_t length, const char *prefix) {
    size_t prefix_length = strlen(prefix);
    size_t index;
    if (length < prefix_length) return 0;
    for (index = 0; index < prefix_length; index++)
        if (pk_url_lower((unsigned char)value[index]) != pk_url_lower((unsigned char)prefix[index])) return 0;
    return 1;
}

/* a host label is letters, digits and hyphens: ':' and '@' are refused, so a port or the userinfo trick
   cannot make a look-alike host */
static int pk_url_host_valid(const char *host, size_t length) {
    size_t index;
    size_t label = 0;
    if (!length || length > 253 || host[0] == '.' || host[length - 1] == '.' || host[0] == '-') return 0;
    for (index = 0; index < length; index++) {
        unsigned char c = (unsigned char)host[index];
        if (c == '.') {
            if (!label || host[index - 1] == '-') return 0;
            label = 0;
            continue;
        }
        if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-')) return 0;
        if (++label > 63) return 0;
    }
    return label > 0;
}

static pk_status pk_url_host_after(const char *url, size_t length, size_t scheme_length, pk_span *host) {
    size_t start = scheme_length;
    size_t index = start;
    if (host) *host = PK_SPAN_NONE;
    if (!url || !host) return PK_ERR_INVALID;
    while (index < length && url[index] != '/' && url[index] != '?' && url[index] != '#') index++;
    if (!pk_url_host_valid(url + start, index - start)) return PK_ERR_INVALID;
    host->offset = start;
    host->length = index - start;
    return PK_OK;
}

pk_status pk_url_host(const char *url, size_t length, pk_span *host) {
    if (host) *host = PK_SPAN_NONE;
    if (!url || !host || !pk_url_prefix_ci(url, length, "https://")) return PK_ERR_INVALID;
    return pk_url_host_after(url, length, 8, host);
}

static pk_status pk_url_normalize_scheme(const char *raw, size_t length,
                                         char *out, size_t capacity, size_t *written, int allow_http) {
    char decoded[PK_MAX_URL_BYTES];
    char absolute[PK_MAX_URL_BYTES];
    size_t decoded_length = 0;
    size_t absolute_length = 0;
    size_t scheme_length = 8;
    size_t index;
    pk_span host;


    if (written) *written = 0;
    if (!raw || !out || !capacity) return PK_ERR_INVALID;
    if (!length || length >= sizeof(decoded)) return PK_ERR_INVALID;

    /* markup escapes the ampersands inside a query */
    if (pk_text_decode_entities(raw, length, decoded, sizeof(decoded), &decoded_length) != PK_OK) return PK_ERR_INVALID;
    if (!decoded_length) return PK_ERR_INVALID;

    for (index = 0; index < decoded_length; index++) {
        unsigned char c = (unsigned char)decoded[index];
        /* control bytes, spaces and a stray quote mean the attribute was cut wrong, and a newline would
           forge a header */
        if (c < 0x21 || c == 0x7F || c == '"' || c == '\'' || c == '<' || c == '>' || c == '\\') return PK_ERR_INVALID;
    }

    if (decoded[0] == '/' && decoded_length > 1 && decoded[1] == '/') {
        if (decoded_length - 2 + 8 >= sizeof(absolute)) return PK_ERR_INVALID;
        memcpy(absolute, "https://", 8);
        memcpy(absolute + 8, decoded + 2, decoded_length - 2);
        absolute_length = decoded_length - 2 + 8;
    } else if (decoded[0] == '/') {
        size_t host_length = strlen(pk_url_default_host);
        if (8 + host_length + decoded_length >= sizeof(absolute)) return PK_ERR_INVALID;
        memcpy(absolute, "https://", 8);
        memcpy(absolute + 8, pk_url_default_host, host_length);
        memcpy(absolute + 8 + host_length, decoded, decoded_length);
        absolute_length = 8 + host_length + decoded_length;
    } else if (pk_url_prefix_ci(decoded, decoded_length, "https://")) {
        memcpy(absolute, decoded, decoded_length);
        absolute_length = decoded_length;
        scheme_length = 8;
    } else if (allow_http && pk_url_prefix_ci(decoded, decoded_length, "http://")) {
        memcpy(absolute, decoded, decoded_length);
        absolute_length = decoded_length;
        scheme_length = 7;
    } else {
        /* http, data, javascript and bare relative paths are never fetched or handed to a web view */
        return PK_ERR_INVALID;
    }

    if (pk_url_host_after(absolute, absolute_length, scheme_length, &host) != PK_OK) return PK_ERR_INVALID;
    if (absolute_length >= capacity) {
        out[0] = '\0';
        return PK_ERR_TRUNCATED;
    }
    memcpy(out, absolute, absolute_length);
    out[absolute_length] = '\0';
    if (written) *written = absolute_length;
    return PK_OK;
}

pk_status pk_url_normalize(const char *raw, size_t length,
                           char *out, size_t capacity, size_t *written) {
    return pk_url_normalize_scheme(raw, length, out, capacity, written, 0);
}

pk_status pk_url_normalize_link(const char *raw, size_t length,
                                char *out, size_t capacity, size_t *written) {
    return pk_url_normalize_scheme(raw, length, out, capacity, written, 1);
}
