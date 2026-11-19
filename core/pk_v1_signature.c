#include "pk_v1_signature.h"
#include <stdio.h>
#include <string.h>

int pk_v1_signature(const char *method, const char *token, const char *values,
                    pk_v1_md5_fn md5, char *out, size_t capacity) {
    static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    static const char digits[] = "0123456789abcdef";
    unsigned char digest[16];
    char input[16384], hex[32];
    size_t i, j;
    int n;
    if (out && capacity) out[0] = 0;
    if (!method || !token || !values || !md5 || !out || capacity < 45) return 0;
    n = snprintf(input, sizeof(input), "kmq4!2cPl)peZ,%s,%s,%s", method, token, values);
    if (n < 0 || (size_t)n >= sizeof(input)) return 0;
    if (md5((const unsigned char *)input, (size_t)n, digest) != 0) return 0;
    for (i = 0; i < sizeof(digest); ++i) {
        hex[i * 2] = digits[digest[i] >> 4];
        hex[i * 2 + 1] = digits[digest[i] & 15];
    }
    for (i = 0, j = 0; i < sizeof(hex); i += 3) {
        unsigned a = (unsigned char)hex[i];
        unsigned b = i + 1 < sizeof(hex) ? (unsigned char)hex[i + 1] : 0;
        unsigned c = i + 2 < sizeof(hex) ? (unsigned char)hex[i + 2] : 0;
        out[j++] = alphabet[a >> 2];
        out[j++] = alphabet[((a & 3) << 4) | (b >> 4)];
        out[j++] = i + 1 < sizeof(hex) ? alphabet[((b & 15) << 2) | (c >> 6)] : '=';
        out[j++] = i + 2 < sizeof(hex) ? alphabet[c & 63] : '=';
    }
    out[j] = 0;
    return 1;
}
