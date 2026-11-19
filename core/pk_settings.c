#include "pk_settings.h"

int pk_settings_user_id(const char *text, size_t length, long *value) {
    size_t index;
    long result = 0;
    if (value) *value = 0;
    if (!text || !value || !length || length > 10) return 0;
    for (index = 0; index < length; index++) {
        int digit;
        if (text[index] < '0' || text[index] > '9') return 0;
        digit = text[index] - '0';
        if (result > (2000000000L - digit) / 10) return 0;
        result = result * 10 + digit;
    }
    if (!result) return 0;
    *value = result;
    return 1;
}

int pk_settings_choice_value(pk_settings_choice choice, size_t index, long *value) {
    static const long posts[] = {-15, -10, -5, 0, 5, 10, 15};
    static const long comments[] = {0, -4, -3, -2, -1};
    if (value) *value = 0;
    if (!value) return 0;
    if (choice == PK_SETTINGS_POST_RATING && index < sizeof(posts) / sizeof(posts[0])) *value = posts[index];
    else if (choice == PK_SETTINGS_COMMENT_RATING && index < sizeof(comments) / sizeof(comments[0])) *value = comments[index];
    else if (choice == PK_SETTINGS_COMMENT_DEPTH && index < 10) *value = index == 9 ? 0 : (long)index + 1;
    else return 0;
    return 1;
}
