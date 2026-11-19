#include <assert.h>
#include <string.h>

#include "pk_url.h"

static void check(const char *raw, const char *expected) {
    char out[PK_MAX_URL_BYTES];
    size_t written = 0;
    assert(pk_url_normalize(raw, strlen(raw), out, sizeof(out), &written) == PK_OK);
    assert(!strcmp(out, expected));
    assert(written == strlen(expected));
}

static void check_rejected(const char *raw) {
    char out[PK_MAX_URL_BYTES];
    size_t written = 1;
    assert(pk_url_normalize(raw, strlen(raw), out, sizeof(out), &written) == PK_ERR_INVALID);
    assert(written == 0);
}

static void check_host(const char *url, const char *expected) {
    pk_span host;
    assert(pk_url_host(url, strlen(url), &host) == PK_OK);
    assert(host.length == strlen(expected));
    assert(!memcmp(url + host.offset, expected, host.length));
}

static void test_absolute(void) {
    check("https://pikabu.ru/story/x_123", "https://pikabu.ru/story/x_123");
    check("https://cs14.pikabu.ru/post_img/2024/a.jpg", "https://cs14.pikabu.ru/post_img/2024/a.jpg");
    /* the scheme is compared without case, the rest is left byte for byte */
    check("HTTPS://pikabu.ru/A", "HTTPS://pikabu.ru/A");
}

static void test_relative(void) {
    check("//cs14.pikabu.ru/a.jpg", "https://cs14.pikabu.ru/a.jpg");
    check("/story/x_123", "https://pikabu.ru/story/x_123");
    check("/", "https://pikabu.ru/");
}

static void test_entities(void) {
    /* markup escapes the query separators, so the raw attribute is not the url */
    check("/search/?q=a&amp;page=2", "https://pikabu.ru/search/?q=a&page=2");
    check("https://pikabu.ru/a&#x2F;b", "https://pikabu.ru/a/b");
    check("https://pikabu.ru/a&#47;b", "https://pikabu.ru/a/b");
}

static void test_rejected(void) {
    check_rejected("");
    /* only https is fetchable; the rest are ways to run or embed something */
    check_rejected("http://pikabu.ru/a");
    check_rejected("javascript:alert(1)");
    check_rejected("data:text/html,<b>x</b>");
    check_rejected("story/x_123");
    check_rejected("ftp://pikabu.ru/a");
    /* userinfo makes a look-alike host read as the real one */
    check_rejected("https://pikabu.ru@evil.example/a");
    check_rejected("https://user:pw@pikabu.ru/a");
    /* an explicit port does not match the scheme this app speaks */
    check_rejected("https://pikabu.ru:8443/a");
    /* a newline in an attribute is how a request header gets forged */
    check_rejected("https://pikabu.ru/a\r\nX-Evil: 1");
    check_rejected("https://pikabu.ru/a b");
    check_rejected("https://pikabu.ru/a\"b");
    check_rejected("https://pikabu.ru/a\\b");
    /* no host at all */
    check_rejected("https://");
    check_rejected("https:///path");
    check_rejected("//");
    check_rejected("https://.pikabu.ru/a");
    check_rejected("https://pikabu.ru./a");
    check_rejected("https://pik--abu-.ru/a");
}

static void test_truncation(void) {
    char out[16];
    size_t written = 1;
    assert(pk_url_normalize("/story/a_very_long_one", 22, out, sizeof(out), &written) == PK_ERR_TRUNCATED);
    /* a cut url points somewhere else, so nothing usable is handed back */
    assert(written == 0);
    assert(out[0] == '\0');
}

static void test_host(void) {
    check_host("https://pikabu.ru/story/x", "pikabu.ru");
    check_host("https://cs14.pikabu.ru/a.jpg?v=2", "cs14.pikabu.ru");
    check_host("https://pikabu.ru", "pikabu.ru");
    check_host("https://pikabu.ru?q=1", "pikabu.ru");
}

static void check_link(const char *raw, const char *expected) {
    char out[PK_MAX_URL_BYTES];
    size_t written = 0;
    assert(pk_url_normalize_link(raw, strlen(raw), out, sizeof(out), &written) == PK_OK);
    assert(!strcmp(out, expected));
    assert(written == strlen(expected));
}

static void check_link_rejected(const char *raw) {
    char out[PK_MAX_URL_BYTES];
    size_t written = 1;
    assert(pk_url_normalize_link(raw, strlen(raw), out, sizeof(out), &written) == PK_ERR_INVALID);
    assert(written == 0);
}

/* a tapped link goes to the system browser, so plain http and any host are fine, everything that could run
   or smuggle stays refused */
static void test_links(void) {
    check_link("http://example.com/a?b=1&amp;c=2", "http://example.com/a?b=1&c=2");
    check_link("https://example.com/a", "https://example.com/a");
    check_link("HTTP://Example.com/", "HTTP://Example.com/");
    check_link("/story/x_1", "https://pikabu.ru/story/x_1");
    check_link("//cdn.example.com/a", "https://cdn.example.com/a");
    check_link_rejected("");
    check_link_rejected("javascript:alert(1)");
    check_link_rejected("mailto:a@example.com");
    check_link_rejected("data:text/html,x");
    check_link_rejected("ftp://example.com/a");
    check_link_rejected("#comments");
    check_link_rejected("http://user@example.com/");
    check_link_rejected("http://example.com:8080/");
    check_link_rejected("http://example.com/a b");
    check_link_rejected("http://example.com/a\r\nX: 1");
    check_link_rejected("http://");
    check_link_rejected("http:///x");
    /* the fetch rule is unchanged: the same http address is still refused there */
    check_rejected("http://example.com/a");
}

int main(void) {
    test_absolute();
    test_relative();
    test_entities();
    test_rejected();
    test_truncation();
    test_host();
    test_links();
    return 0;
}
