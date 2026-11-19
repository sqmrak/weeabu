#include "pk_accent.h"
#include <math.h>

static int hex_digit(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

int pk_accent_parse_hex(const char *text, size_t length, float *hue, float *saturation, float *brightness) {
    unsigned rgb = 0;
    size_t i;
    float r, g, b, high, low, span, h = 0;
    if (!text || !hue || !saturation || !brightness || (length != 3 && length != 6)) return 0;
    for (i = 0; i < length; i++) {
        int digit = hex_digit(text[i]);
        if (digit < 0) return 0;
        rgb = (rgb << 4) | (unsigned)digit;
        if (length == 3) rgb = (rgb << 4) | (unsigned)digit;
    }
    r = ((rgb >> 16) & 255) / 255.0f;
    g = ((rgb >> 8) & 255) / 255.0f;
    b = (rgb & 255) / 255.0f;
    high = fmaxf(r, fmaxf(g, b)); low = fminf(r, fminf(g, b)); span = high - low;
    if (span > 0) {
        if (high == r) h = fmodf((g - b) / span, 6);
        else if (high == g) h = (b - r) / span + 2;
        else h = (r - g) / span + 4;
        h *= 60;
        if (h < 0) h += 360;
        *hue = h;
    }
    *saturation = high > 0 ? span / high : 0;
    *brightness = fminf(1, high / 0.745f);
    return 1;
}

void pk_accent_rgb(float hue, float saturation, float brightness, float *red, float *green, float *blue) {
    float sector, chroma, x, match, r = 0, g = 0, b = 0;
    hue = isfinite(hue) ? fmodf(hue, 360) : 0;
    if (hue < 0) hue += 360;
    saturation = isfinite(saturation) ? fmaxf(0, fminf(1, saturation)) : 0;
    brightness = isfinite(brightness) ? fmaxf(0, fminf(1, brightness)) : 0;
    sector = hue / 60; chroma = brightness * 0.745f * saturation;
    x = chroma * (1 - fabsf(fmodf(sector, 2) - 1));
    if (sector < 1) { r = chroma; g = x; }
    else if (sector < 2) { r = x; g = chroma; }
    else if (sector < 3) { g = chroma; b = x; }
    else if (sector < 4) { g = x; b = chroma; }
    else if (sector < 5) { r = x; b = chroma; }
    else { r = chroma; b = x; }
    match = brightness * 0.745f - chroma;
    if (red) *red = r + match;
    if (green) *green = g + match;
    if (blue) *blue = b + match;
}
