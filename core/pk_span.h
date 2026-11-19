#ifndef PK_SPAN_H
#define PK_SPAN_H

#include <stddef.h>

/* slices of the caller's buffer, so the core never allocates and the objective-c layer decides what to keep */
typedef struct {
    size_t offset;
    size_t length;
} pk_span;

#define PK_SPAN_NONE ((pk_span){ 0, 0 })
#define PK_SPAN_PTR(base, span) ((base) + (span).offset)

#endif
