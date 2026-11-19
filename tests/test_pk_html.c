#include <assert.h>
#include <string.h>

#include "pk_html.h"

static pk_html doc;

static void load(const char *html) {
    assert(pk_html_init(&doc, html, strlen(html)) == PK_OK);
}

static void check_span(pk_span span, const char *expected) {
    assert(span.length == strlen(expected));
    assert(!memcmp(doc.data + span.offset, expected, span.length));
}

static void test_find(void) {
    pk_span tag;
    load("<html><body><div class=\"a b\">x</div><div class=\"c\">y</div></body></html>");
    assert(pk_html_find(&doc, 0, "div", NULL, &tag) == PK_OK);
    check_span(tag, "<div class=\"a b\">");
    assert(pk_html_find(&doc, 0, "div", "b", &tag) == PK_OK);
    check_span(tag, "<div class=\"a b\">");
    assert(pk_html_find(&doc, 0, "div", "c", &tag) == PK_OK);
    check_span(tag, "<div class=\"c\">");
    assert(pk_html_find(&doc, 0, "div", "missing", &tag) == PK_ERR_NOT_FOUND);
    assert(pk_html_find(&doc, 0, "span", NULL, &tag) == PK_ERR_NOT_FOUND);
    /* the name matches whole, so <div> is not found by searching for <d> */
    assert(pk_html_find(&doc, 0, "d", NULL, &tag) == PK_ERR_NOT_FOUND);
    /* iterating means searching again from the end of the last hit */
    assert(pk_html_find(&doc, 0, "div", NULL, &tag) == PK_OK);
    assert(pk_html_find(&doc, tag.offset + tag.length, "div", NULL, &tag) == PK_OK);
    check_span(tag, "<div class=\"c\">");
}

static void test_class_is_a_whole_token(void) {
    pk_span tag;
    load("<a class=\"story__title-link\">x</a><a class=\"story__title\">y</a>");
    assert(pk_html_find(&doc, 0, "a", "story__title", &tag) == PK_OK);
    /* a substring of another class must not match, or every card picks the
       wrong element out of its own markup */
    check_span(tag, "<a class=\"story__title\">");
    load("<a class=\"pre story__user-link post\">x</a>");
    assert(pk_html_find(&doc, 0, "a", "story__user-link", &tag) == PK_OK);
    load("<a class=\"story__user-linkage\">x</a>");
    assert(pk_html_find(&doc, 0, "a", "story__user-link", &tag) == PK_ERR_NOT_FOUND);
}

static void test_attributes(void) {
    pk_span tag;
    pk_span value;
    const char *names[3];
    load("<img src='s.jpg' data-src=\"d.jpg\" data-large-image=big.jpg width=100 hidden>");
    assert(pk_html_find(&doc, 0, "img", NULL, &tag) == PK_OK);
    assert(pk_html_attr(&doc, tag, "src", &value) == PK_OK);
    check_span(value, "s.jpg");
    assert(pk_html_attr(&doc, tag, "data-src", &value) == PK_OK);
    check_span(value, "d.jpg");
    /* an unquoted value ends at the next space */
    assert(pk_html_attr(&doc, tag, "data-large-image", &value) == PK_OK);
    check_span(value, "big.jpg");
    assert(pk_html_attr(&doc, tag, "width", &value) == PK_OK);
    check_span(value, "100");
    /* a valueless attribute has no value to report */
    assert(pk_html_attr(&doc, tag, "hidden", &value) == PK_ERR_NOT_FOUND);
    assert(pk_html_attr(&doc, tag, "nope", &value) == PK_ERR_NOT_FOUND);
    /* the element name is not an attribute of itself */
    assert(pk_html_attr(&doc, tag, "img", &value) == PK_ERR_NOT_FOUND);

    names[0] = "data-large-image";
    names[1] = "data-src";
    names[2] = "src";
    assert(pk_html_attr_any(&doc, tag, names, 3, &value) == PK_OK);
    check_span(value, "big.jpg");

    /* '>' inside a quoted value does not end the tag */
    load("<a href=\"/a?x=1>2\" title='y>z'>link</a>");
    assert(pk_html_find(&doc, 0, "a", NULL, &tag) == PK_OK);
    assert(pk_html_attr(&doc, tag, "href", &value) == PK_OK);
    check_span(value, "/a?x=1>2");
    assert(pk_html_attr(&doc, tag, "title", &value) == PK_OK);
    check_span(value, "y>z");

    /* whitespace around '=' is legal markup */
    load("<a href = \"/p\" >x</a>");
    assert(pk_html_find(&doc, 0, "a", NULL, &tag) == PK_OK);
    assert(pk_html_attr(&doc, tag, "href", &value) == PK_OK);
    check_span(value, "/p");

    /* an empty value is present and empty, not missing */
    load("<a href=\"\">x</a>");
    assert(pk_html_find(&doc, 0, "a", NULL, &tag) == PK_OK);
    assert(pk_html_attr(&doc, tag, "href", &value) == PK_OK);
    assert(value.length == 0);
}

static void test_body(void) {
    pk_span tag;
    pk_span body;
    load("<div class=\"outer\">a<div>b</div>c</div>tail");
    assert(pk_html_find(&doc, 0, "div", "outer", &tag) == PK_OK);
    assert(pk_html_body(&doc, tag, &body) == PK_OK);
    /* the nested div of the same name must not end the outer one early */
    check_span(body, "a<div>b</div>c");

    load("<article>x</article>");
    assert(pk_html_find(&doc, 0, "article", NULL, &tag) == PK_OK);
    assert(pk_html_body(&doc, tag, &body) == PK_OK);
    check_span(body, "x");

    /* a self closing tag has no content */
    load("<div><img src=\"a.jpg\"/>after</div>");
    assert(pk_html_find(&doc, 0, "img", NULL, &tag) == PK_OK);
    assert(pk_html_body(&doc, tag, &body) == PK_OK);
    assert(body.length == 0);

    /* an element the page never closes still yields what there is */
    load("<div class=\"outer\">tail of a cut page");
    assert(pk_html_find(&doc, 0, "div", "outer", &tag) == PK_OK);
    assert(pk_html_body(&doc, tag, &body) == PK_ERR_TRUNCATED);
    check_span(body, "tail of a cut page");
}

static void test_script_bodies_are_opaque(void) {
    pk_span tag;
    pk_span body;
    /* the "</div>" below is a javascript string, not a tag */
    load("<div class=\"outer\">a<script>var s = \"</div>\";</script>b</div>tail");
    assert(pk_html_find(&doc, 0, "div", "outer", &tag) == PK_OK);
    assert(pk_html_body(&doc, tag, &body) == PK_OK);
    check_span(body, "a<script>var s = \"</div>\";</script>b");

    /* and a card written inside a script is not a card on the page */
    load("<script>var t = '<article class=\"story\">fake</article>';</script>"
         "<article class=\"story\">real</article>");
    assert(pk_html_find(&doc, 0, "article", "story", &tag) == PK_OK);
    assert(pk_html_body(&doc, tag, &body) == PK_OK);
    check_span(body, "real");
}

static void test_bounds(void) {
    pk_span tag;
    pk_span body;
    pk_html empty;
    assert(pk_html_init(&empty, NULL, 0) == PK_ERR_INVALID);
    assert(pk_html_init(&empty, "x", PK_MAX_DOCUMENT_BYTES + 1) == PK_ERR_TOO_LARGE);
    assert(empty.data == NULL && empty.length == 0);

    /* truncated markup must terminate, not read past the buffer */
    load("<");
    assert(pk_html_find(&doc, 0, "div", NULL, &tag) == PK_ERR_NOT_FOUND);
    load("<div");
    assert(pk_html_find(&doc, 0, "div", NULL, &tag) == PK_OK);
    assert(pk_html_body(&doc, tag, &body) == PK_ERR_TRUNCATED);
    load("<div class=\"a");
    assert(pk_html_find(&doc, 0, "div", "a", &tag) == PK_ERR_NOT_FOUND);
    load("");
    assert(pk_html_find(&doc, 0, "div", NULL, &tag) == PK_ERR_NOT_FOUND);

    /* searching past the end is a caller bug, not a read */
    load("<div></div>");
    assert(pk_html_find(&doc, doc.length + 1, "div", NULL, &tag) == PK_ERR_INVALID);
}

int main(void) {
    test_find();
    test_class_is_a_whole_token();
    test_attributes();
    test_body();
    test_script_bodies_are_opaque();
    test_bounds();
    return 0;
}
