#ifndef PK_SETTINGS_H
#define PK_SETTINGS_H

#include <stddef.h>

int pk_settings_user_id(const char *text, size_t length, long *value);

typedef enum {
    PK_SETTINGS_POST_RATING = 1,
    PK_SETTINGS_COMMENT_RATING = 2,
    PK_SETTINGS_COMMENT_DEPTH = 3
} pk_settings_choice;

/* the choices of the original client, depth 10 is sent as 0 */
int pk_settings_choice_value(pk_settings_choice choice, size_t index, long *value);

#endif
