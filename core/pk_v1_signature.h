#ifndef PK_V1_SIGNATURE_H
#define PK_V1_SIGNATURE_H
#include <stddef.h>

typedef int (*pk_v1_md5_fn)(const unsigned char *, size_t, unsigned char *);

/* values must already be in java utf-16 order */
int pk_v1_signature(const char *method, const char *token, const char *values,
                    pk_v1_md5_fn md5, char *out, size_t capacity);
#endif
