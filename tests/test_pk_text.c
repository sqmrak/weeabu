#include <assert.h>
#include <string.h>

#include "pk_text.h"

static void check_plain(const char *html, const char *expected) {
    char out[512];
    size_t written = 0;
    assert(pk_text_plain(html, strlen(html), out, sizeof(out), &written) == PK_OK);
    assert(written == strlen(expected));
    assert(!strcmp(out, expected));
}

static void check_entities(const char *in, const char *expected) {
    char out[256];
    size_t written = 0;
    assert(pk_text_decode_entities(in, strlen(in), out, sizeof(out), &written) == PK_OK);
    assert(!strcmp(out, expected));
    assert(written == strlen(expected));
}

static void check_number(const char *text, long expected) {
    long value = -12345;
    assert(pk_number_compact(text, strlen(text), &value) == PK_OK);
    assert(value == expected);
}

static void check_number_rejected(const char *text) {
    long value = 777;
    assert(pk_number_compact(text, strlen(text), &value) == PK_ERR_INVALID);
    assert(value == 0);
}

static void check_format(long value, const char *expected) {
    char out[32];
    size_t written = 0;
    assert(pk_number_format(value, out, sizeof(out), &written) == PK_OK);
    assert(!strcmp(out, expected));
    assert(written == strlen(expected));
}

static void test_entities(void) {
    check_entities("plain", "plain");
    check_entities("a &amp; b", "a & b");
    check_entities("&lt;tag&gt;", "<tag>");
    check_entities("&quot;q&quot; &#39;a&#39; &#x27;b&#x27;", "\"q\" 'a' 'b'");
    check_entities("&mdash;&ndash;", "--");
    check_entities("&minus;", "\xe2\x88\x92");
    check_entities("&hellip;", "\xe2\x80\xa6");
    /* the word joiner pikabu sprinkles into titles carries no glyph */
    check_entities("a&#8288;b", "ab");
    /* cyrillic through the numeric form: u+0410 */
    check_entities("&#1040;", "\xd0\x90");
    check_entities("&#x410;", "\xd0\x90");
    /* anything the table does not know stays exactly as it arrived */
    check_entities("&unknownthing; &amp", "&unknownthing; &amp");
    check_entities("&;", "&;");
    check_entities("&#;", "&#;");
    /* a surrogate half is not a character and must not be re-encoded */
    check_entities("&#xD800;", "&#xD800;");
    check_entities("&#x110000;", "&#x110000;");
}

static void test_plain(void) {
    check_plain("<p>hello</p>", "hello");
    check_plain("<b>bold</b> text", "bold text");
    check_plain("a<br>b", "a\nb");
    check_plain("a<br/>b<br />c", "a\nb\nc");
    check_plain("<p>one</p><p>two</p>", "one\ntwo");
    /* runs of whitespace collapse, and the edges are trimmed */
    check_plain("   a \t\n  b   ", "a b");
    check_plain("<div>  </div>", "");
    /* an attribute value containing '>' must not end the tag early */
    check_plain("<a title=\"a>b\">link</a>", "link");
    check_plain("<a title='a>b'>link</a>", "link");
    /* script and style bodies are code, not the post someone is reading */
    check_plain("<p>a</p><script>var x = 1 < 2;</script><p>b</p>", "a\nb");
    check_plain("<style>.c{color:red}</style>text", "text");
    check_plain("<script>never closed", "");
    /* entities inside markup decode, and an entity space collapses like a space */
    check_plain("<p>a&nbsp;&nbsp;b</p>", "a b");
    check_plain("<p>&laquo;\xd0\xb4\xd0\xb0&raquo;</p>", "\xc2\xab\xd0\xb4\xd0\xb0\xc2\xbb");
    /* a truncated tag at the end of a page must not leak markup */
    check_plain("text<div class=\"x", "text");
    /* paragraphs separate with one newline, and no run of empty ones ever
       produces more than a single blank line */
    check_plain("<p>a</p><p>b</p>", "a\nb");
    check_plain("<p>a</p><p></p><p>b</p>", "a\n\nb");
    check_plain("<p>a</p><p></p><p></p><p></p><p>b</p>", "a\n\nb");
    check_plain("a<br><br><br><br>b", "a\n\nb");
}

static void test_plain_truncation(void) {
    char out[8];
    size_t written = 0;
    assert(pk_text_plain("abcdefghij", 10, out, sizeof(out), &written) == PK_ERR_TRUNCATED);
    /* the caller learns the full length and still gets a valid prefix */
    assert(written == 10);
    assert(!strcmp(out, "abcdefg"));
    assert(pk_text_plain("abc", 3, out, 0, &written) == PK_ERR_TRUNCATED);
    assert(written == 3);
    assert(pk_text_plain("abc", PK_MAX_DOCUMENT_BYTES + 1, out, sizeof(out), &written) == PK_ERR_TOO_LARGE);
    assert(written == 0);
}

static void test_numbers(void) {
    check_number("0", 0);
    check_number("348", 348);
    check_number("-12", -12);
    check_number("+7", 7);
    /* the rating block renders u+2212, not a hyphen */
    check_number("\xe2\x88\x92""42", -42);
    check_number("1,2K", 1200);
    check_number("1.2k", 1200);
    check_number("3,4M", 3400000);
    /* cyrillic suffixes, upper and lower case */
    check_number("12\xd0\xba", 12000);
    check_number("12\xd0\x9a", 12000);
    check_number("2\xd0\xbc", 2000000);
    check_number("2\xd0\x9c", 2000000);
    /* thousands grouped with a space, which is what &nbsp; decodes to */
    check_number("1 234", 1234);
    check_number("  56  ", 56);

    check_number_rejected("");
    check_number_rejected("k");
    check_number_rejected("abc");
    check_number_rejected("12x");
    check_number_rejected("1,2");
    check_number_rejected("1,2K3");
    check_number_rejected("99999999999999999999");
    check_number_rejected("-999999999K");
    check_number_rejected("2000001K");
}

static void test_profile_rating(void) {
    static const struct { const char *text; int valid; int negative; } cases[] = {
        {"-123", 1, 1}, {"0", 1, 0}, {"101686", 1, 0}, {"-1.25", 1, 1},
        {"2000000000", 1, 0}, {"2000000001", 0, 0}, {"", 0, 0},
        {"-", 0, 0}, {"1.", 0, 0}, {".5", 0, 0}, {"1e3", 0, 0},
        {"-1xyz", 0, 0}, {" 1", 0, 0}, {"999999999999999999999", 0, 0}
    };
    size_t index;
    for (index = 0; index < sizeof(cases) / sizeof(cases[0]); index++) {
        int negative = 42;
        assert(pk_profile_rating(cases[index].text, strlen(cases[index].text), &negative) == cases[index].valid);
        assert(negative == cases[index].negative);
    }
}

static void test_format(void) {
    check_format(0, "0");
    check_format(7, "7");
    check_format(-42, "-42");
    check_format(999, "999");
    check_format(1000, "1k");
    check_format(1200, "1,2k");
    check_format(-1200, "-1,2k");
    check_format(9900, "9,9k");
    check_format(12345, "12k");
    check_format(999999, "999k");
}

static int count_label(const char *text) {
    return pk_text_is_count_label(text, strlen(text));
}

static void test_count_label(void) {
    assert(count_label("+3"));
    assert(count_label("12"));
    assert(count_label("1,2k"));
    assert(count_label(""));
    assert(!count_label("\xd0\xbc\xd0\xb5\xd0\xbc"));
    assert(!count_label("cats"));
    /* a bare suffix is not a count, it is a one letter tag */
    assert(!count_label("k"));
}

int main(void) {
    test_entities();
    test_plain();
    test_plain_truncation();
    test_numbers();
    test_profile_rating();
    test_format();
    test_count_label();
    return 0;
}
