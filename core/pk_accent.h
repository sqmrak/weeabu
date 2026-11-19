#ifndef PK_ACCENT_H
#define PK_ACCENT_H
#include <stddef.h>
int pk_accent_parse_hex(const char *text, size_t length, float *hue, float *saturation, float *brightness);
void pk_accent_rgb(float hue, float saturation, float brightness, float *red, float *green, float *blue);
#endif
