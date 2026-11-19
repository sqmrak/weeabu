#include <assert.h>
#include <string.h>
#include "pk_settings.h"

static void check_id(const char *text, int valid, long expected) {
    long value = -1;
    assert(pk_settings_user_id(text, strlen(text), &value) == valid);
    assert(value == expected);
}

int main(void) {
    long value;
    size_t i;
    static const long post[] = {-15, -10, -5, 0, 5, 10, 15};
    static const long comment[] = {0, -4, -3, -2, -1};
    check_id("1", 1, 1);
    check_id("1573995", 1, 1573995);
    check_id("2000000000", 1, 2000000000L);
    check_id("2000000001", 0, 0);
    check_id("0", 0, 0);
    check_id("", 0, 0);
    check_id("-1", 0, 0);
    check_id("1.0", 0, 0);
    check_id("1x", 0, 0);
    check_id("99999999999", 0, 0);
    for (i = 0; i < sizeof(post) / sizeof(post[0]); i++) {
        assert(pk_settings_choice_value(PK_SETTINGS_POST_RATING, i, &value));
        assert(value == post[i]);
    }
    for (i = 0; i < sizeof(comment) / sizeof(comment[0]); i++) {
        assert(pk_settings_choice_value(PK_SETTINGS_COMMENT_RATING, i, &value));
        assert(value == comment[i]);
    }
    for (i = 0; i < 10; i++) {
        assert(pk_settings_choice_value(PK_SETTINGS_COMMENT_DEPTH, i, &value));
        assert(value == (i == 9 ? 0 : (long)i + 1));
    }
    assert(!pk_settings_choice_value(PK_SETTINGS_POST_RATING, 7, &value) && value == 0);
    assert(!pk_settings_choice_value(PK_SETTINGS_COMMENT_DEPTH, 10, &value) && value == 0);
    assert(!pk_settings_choice_value((pk_settings_choice)99, 0, &value) && value == 0);
    return 0;
}
