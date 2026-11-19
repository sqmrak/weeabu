#ifndef PK_TEXT_H
#define PK_TEXT_H

#include <stddef.h>

#include "pk_status.h"

/* `written` always gets the byte count, even when truncated */
pk_status pk_text_decode_entities(const char *in, size_t in_length,
                                  char *out, size_t capacity, size_t *written);

pk_status pk_text_plain(const char *html, size_t length,
                        char *out, size_t capacity, size_t *written);

/* also cyrillic suffixes ("12К", "1,5М") and the u+2212 minus, PK_ERR_INVALID for anything else */
pk_status pk_number_compact(const char *text, size_t length, long *value);

int pk_rating_label(const char *text, size_t length, long *value);

int pk_profile_rating(const char *text, size_t length, int *negative);

/* 1200 -> "1,2k", 12345 -> "12k", 999 -> "999" */
pk_status pk_number_format(long value, char *out, size_t capacity, size_t *written);

/* tells a real tag from the "+3" counter at the end of a tag list */
int pk_text_is_count_label(const char *text, size_t length);

#endif
