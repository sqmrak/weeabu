#include "pk_accent.h"
#include <assert.h>
#include <math.h>
#include <string.h>
int main(void) {
    float h = 120, s = 0, v = 0, r, g, b;
    assert(pk_accent_parse_hex("548d27", 6, &h, &s, &v));
    pk_accent_rgb(h, s, v, &r, &g, &b);
    assert(fabsf(r - 84.0f/255) < 0.0001f && fabsf(g - 141.0f/255) < 0.0001f && fabsf(b - 39.0f/255) < 0.0001f);
    assert(pk_accent_parse_hex("f00", 3, &h, &s, &v) && h == 0 && s == 1 && v == 1);
    assert(pk_accent_parse_hex("000", 3, &h, &s, &v) && h == 0 && s == 0 && v == 0);
    h = 245;
    assert(pk_accent_parse_hex("777777", 6, &h, &s, &v) && h == 245 && s == 0);
    assert(!pk_accent_parse_hex("x00000", 6, &h, &s, &v));
    assert(!pk_accent_parse_hex("12", 2, &h, &s, &v));
    assert(!pk_accent_parse_hex(NULL, 0, &h, &s, &v));
    pk_accent_rgb(360, 1, 1, &r, &g, &b);
    assert(fabsf(r - 0.745f) < 0.0001f && g == 0 && b == 0);
    return 0;
}
