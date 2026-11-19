#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "pk_story.h"
#include "pk_text.h"
#include "pk_url.h"

#include "story_fixture.inc"

static pk_html doc;

static void load(const char *html) {
    assert(pk_html_init(&doc, html, strlen(html)) == PK_OK);
}

static void check_span(pk_span span, const char *expected) {
    assert(span.length == strlen(expected));
    assert(!memcmp(doc.data + span.offset, expected, span.length));
}

static void check_plain(pk_span span, const char *expected) {
    char text[2048];
    size_t written = 0;
    assert(pk_text_plain(doc.data + span.offset, span.length, text, sizeof(text), &written) == PK_OK);
    assert(!strcmp(text, expected));
}

static void test_real_content(void) {
    pk_span content;
    pk_story_block blocks[PK_STORY_MAX_BLOCKS];
    size_t count;
    char url[PK_MAX_URL_BYTES];

    load(pk_fixture_story_content);
    assert(pk_story_content(&doc, &content) == PK_OK);
    count = pk_story_blocks(&doc, content, blocks, PK_STORY_MAX_BLOCKS);
    /* this post is a single image with no caption */
    assert(count == 1);
    assert(blocks[0].type == PK_BLOCK_IMAGE);
    check_span(blocks[0].url, "https://cs4.pikabu.ru/s/2026/09/10/06/ylnl7cmk.jpg");
    /* what the core reports has to survive the url rules unchanged */
    assert(pk_url_normalize(doc.data + blocks[0].url.offset, blocks[0].url.length,
                            url, sizeof(url), NULL) == PK_OK);
    assert(!strcmp(url, "https://cs4.pikabu.ru/s/2026/09/10/06/ylnl7cmk.jpg"));
    /* the page reserves the box before the picture arrives, which is what lets the row keep its height */
    assert(blocks[0].width > 0 && blocks[0].height > 0);
}

static void test_media_boxes(void) {
    pk_span content;
    pk_story_block blocks[PK_STORY_MAX_BLOCKS];
    long width = 0, height = 0;
    load("<div class=\"story__content-inner\">"
         "<div class=\"story-block\"><svg class=\"story-image__stretch\" viewBox=\"0 0 700 490\"></svg><img data-src=\"/a.jpg\"></div>"
         "<div class=\"story-block\"><img data-src=\"/b.jpg\"></div>"
         "<div class=\"story-block\"><svg class=\"story-image__stretch\" viewBox=\"0 0 x 5\"></svg><img data-src=\"/c.jpg\"></div>"
         "<div class=\"story-block\"><video data-width=\"480\" data-height=\"640\" data-source=\"/v\"><source src=\"/v.mp4\"></video></div>"
         "<div class=\"story-block\"><video data-width=\"480\" data-source=\"/w\"><source src=\"/w.mp4\"></video></div></div>");
    assert(pk_story_content(&doc, &content) == PK_OK);
    assert(pk_story_blocks(&doc, content, blocks, PK_STORY_MAX_BLOCKS) == 5);
    /* each image takes the box of its own svg: the second has none and must not borrow the first's */
    assert(blocks[0].width == 700 && blocks[0].height == 490);
    assert(blocks[1].width == 0 && blocks[1].height == 0);
    assert(blocks[2].width == 0 && blocks[2].height == 0);
    assert(blocks[3].width == 480 && blocks[3].height == 640);
    /* half a size is no size */
    assert(blocks[4].width == 0 && blocks[4].height == 0);
    assert(pk_story_view_box("0 0 700.5 490", 13, &width, &height) && width == 700 && height == 490);
    assert(!pk_story_view_box("0 0 700", 7, &width, &height));
    assert(!pk_story_view_box("0 0 0 5", 7, &width, &height));
    assert(!pk_story_view_box("", 0, &width, &height));
}

static void test_real_reactions(void) {
    pk_reaction reactions[PK_REACTIONS_MAX];
    size_t count = 0;
    load(pk_fixture_story_emotions);
    assert(pk_story_reactions(&doc, reactions, PK_REACTIONS_MAX, &count) == PK_OK);
    assert(count > 0);
    assert(reactions[0].id == 6);
    assert(reactions[0].count == 1880);
    /* nobody is signed in in a saved page */
    assert(!reactions[0].active);
}

static void test_blocks(void) {
    pk_span content;
    pk_story_block blocks[PK_STORY_MAX_BLOCKS];
    size_t count;

    load("<div class=\"story__content-inner\">"
         "<p>first</p><img src=\"/a.jpg\"><p>second</p>"
         "<video poster=\"/p.jpg\" data-source=\"/v\" data-duration=\"42\"><source src=\"/v.mp4\" type=\"video/mp4\"></video>"
         "<p>third</p></div>");
    assert(pk_story_content(&doc, &content) == PK_OK);
    count = pk_story_blocks(&doc, content, blocks, PK_STORY_MAX_BLOCKS);
    assert(count == 5);
    assert(blocks[0].type == PK_BLOCK_TEXT);
    check_plain(blocks[0].text, "first");
    assert(blocks[1].type == PK_BLOCK_IMAGE);
    check_span(blocks[1].url, "/a.jpg");
    assert(blocks[2].type == PK_BLOCK_TEXT);
    check_plain(blocks[2].text, "second");
    assert(blocks[3].type == PK_BLOCK_VIDEO);
    /* the file lives on the <source> child, the still and the length on <video> */
    check_span(blocks[3].url, "/v.mp4");
    check_span(blocks[3].poster, "/p.jpg");
    check_span(blocks[3].duration, "42");
    assert(blocks[4].type == PK_BLOCK_TEXT);
    check_plain(blocks[4].text, "third");

    /* markup between blocks that renders to nothing is not a paragraph */
    load("<div class=\"story__content-inner\">"
         "<div>   </div><img src=\"/a.jpg\"><div>\n\t</div></div>");
    assert(pk_story_content(&doc, &content) == PK_OK);
    count = pk_story_blocks(&doc, content, blocks, PK_STORY_MAX_BLOCKS);
    assert(count == 1);
    assert(blocks[0].type == PK_BLOCK_IMAGE);

    /* a media element with no source cannot be rendered and is not a block */
    load("<div class=\"story__content-inner\"><p>t</p><img alt=\"x\"></div>");
    assert(pk_story_content(&doc, &content) == PK_OK);
    count = pk_story_blocks(&doc, content, blocks, PK_STORY_MAX_BLOCKS);
    assert(count == 1);
    assert(blocks[0].type == PK_BLOCK_TEXT);

    /* a text only post is one block */
    load("<div class=\"story__content-inner\"><p>only words</p></div>");
    assert(pk_story_content(&doc, &content) == PK_OK);
    count = pk_story_blocks(&doc, content, blocks, PK_STORY_MAX_BLOCKS);
    assert(count == 1);
    check_plain(blocks[0].text, "only words");

    load("<div>no story content here</div>");
    assert(pk_story_content(&doc, &content) == PK_ERR_NOT_FOUND);
}

static void test_csrf(void) {
    pk_span token;
    load("<script>window.config = {\"csrfToken\":\"abc123\",\"x\":1};</script>");
    assert(pk_story_csrf(&doc, &token) == PK_OK);
    check_span(token, "abc123");

    load("<script>var a = {\"csrfToken\": \"spaced\"};</script>");
    assert(pk_story_csrf(&doc, &token) == PK_OK);
    check_span(token, "spaced");

    /* an empty token is not a token, and the scan keeps looking */
    load("<script>{\"csrfToken\":\"\"}</script><script>{\"csrfToken\":\"real\"}</script>");
    assert(pk_story_csrf(&doc, &token) == PK_OK);
    check_span(token, "real");

    load("<script>{\"csrfToken\":null}</script>");
    assert(pk_story_csrf(&doc, &token) == PK_ERR_NOT_FOUND);
    load("<div>nothing</div>");
    assert(pk_story_csrf(&doc, &token) == PK_ERR_NOT_FOUND);
    assert(token.length == 0);
}

static void test_reactions(void) {
    pk_reaction reactions[PK_REACTIONS_MAX];
    pk_span all;
    size_t count;

    load("<div class=\"emotions\">"
         "<button data-id=\"15\" data-count=\"39\" class=\"emotion-btn\">x</button>"
         "<button data-id=\"1\" data-count=\"7\" class=\"emotion-btn emotion-btn_active\">y</button>"
         "<button data-id=\"0\" data-count=\"3\" class=\"emotion-btn\">bad id</button>"
         "<button data-count=\"3\" class=\"emotion-btn\">no id</button>"
         "<button data-id=\"9\" class=\"emotion-btn\">no count</button>"
         "<button data-id=\"5\" data-count=\"2\" class=\"other-btn\">not a reaction</button>"
         "</div>");
    all.offset = 0;
    all.length = doc.length;
    count = pk_reactions_parse(&doc, all, reactions, PK_REACTIONS_MAX);
    assert(count == 2);
    assert(reactions[0].id == 15 && reactions[0].count == 39 && !reactions[0].active);
    assert(reactions[1].id == 1 && reactions[1].count == 7 && reactions[1].active);

    /* the post's bar is found by its own container, not by any emotion button */
    load("<div class=\"comment\"><button data-id=\"3\" data-count=\"1\" class=\"emotion-btn\">c</button></div>"
         "<div class=\"story__emotions\"><button data-id=\"13\" data-count=\"5\" class=\"emotion-btn\">s</button></div>");
    assert(pk_story_reactions(&doc, reactions, PK_REACTIONS_MAX, &count) == PK_OK);
    assert(count == 1);
    assert(reactions[0].id == 13 && reactions[0].count == 5);

    load("<div>no reactions</div>");
    assert(pk_story_reactions(&doc, reactions, PK_REACTIONS_MAX, &count) == PK_ERR_NOT_FOUND);
    assert(count == 0);
}

static void test_links(void) {
    pk_span hrefs[PK_STORY_MAX_LINKS];
    pk_span range;
    const char *html = "see <a href=\"https://example.com/a?x=1&amp;y=2\">this</a>, "
                       "<a name=\"top\">target</a><a href=\"\">empty</a>"
                       "and <a class=\"l\" href='http://example.org/'>that</a>";
    load(html);
    range.offset = 0;
    range.length = strlen(html);
    assert(pk_story_links(&doc, range, hrefs, PK_STORY_MAX_LINKS) == 2);
    assert(hrefs[0].length == strlen("https://example.com/a?x=1&amp;y=2"));
    assert(!memcmp(doc.data + hrefs[0].offset, "https://example.com/a?x=1&amp;y=2", hrefs[0].length));
    assert(!memcmp(doc.data + hrefs[1].offset, "http://example.org/", hrefs[1].length));
    /* the caller's array is the ceiling */
    assert(pk_story_links(&doc, range, hrefs, 1) == 1);
    assert(pk_story_links(&doc, range, hrefs, 0) == 0);
    assert(pk_story_links(&doc, range, NULL, 4) == 0);
    /* a range past the document is refused, not read */
    range.length = strlen(html) + 1;
    assert(pk_story_links(&doc, range, hrefs, PK_STORY_MAX_LINKS) == 0);
    /* a page full of anchors stops at the bound */
    {
        char many[4096];
        size_t used = 0;
        size_t index;
        for (index = 0; index < 40; index++)
            used += (size_t)snprintf(many + used, sizeof(many) - used, "<a href=\"/a%zu\">x</a>", index);
        load(many);
        range.offset = 0;
        range.length = used;
        assert(pk_story_links(&doc, range, hrefs, PK_STORY_MAX_LINKS) == PK_STORY_MAX_LINKS);
    }
}

static void test_story_rating(void) {
    long score = 99;
    load("<article class=\"story\" data-rating=\"-14\"><div class=\"story__rating-block\"></div></article>");
    assert(pk_story_score(&doc, &score) == PK_OK && score == -14);
    load("<article class=\"story\"><div class=\"story__rating-block\" aria-label=\"5 plus / 12 minus\"><div class=\"story__rating-count\"><svg></svg></div></div></article>");
    assert(pk_story_score(&doc, &score) == PK_OK && score == -7);
    load("<article class=\"story\"><div class=\"story__rating-block\" aria-label=\"pending\"><div class=\"story__rating-count\"><svg></svg></div></div></article>");
    assert(pk_story_score(&doc, &score) == PK_ERR_NOT_FOUND && score == 0);
}

int main(void) {
    test_real_content();
    test_media_boxes();
    test_story_rating();
    test_real_reactions();
    test_blocks();
    test_csrf();
    test_reactions();
    test_links();
    return 0;
}
