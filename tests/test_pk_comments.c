#include <assert.h>
#include <string.h>

#include "pk_comments.h"
#include "pk_story.h"
#include "pk_text.h"

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
    char text[1024];
    size_t written = 0;
    assert(pk_text_plain(doc.data + span.offset, span.length, text, sizeof(text), &written) == PK_OK);
    assert(!strcmp(text, expected));
}

static void test_real_comment(void) {
    pk_comment comments[8];
    size_t count;
    load(pk_fixture_comment_1);
    count = pk_comments_parse(&doc, comments, 8);
    assert(count == 1);
    check_span(comments[0].comment_id, "404063172");
    /* the thread position comes out of data-meta, not out of two guesses */
    check_span(comments[0].parent_id, "0");
    assert(comments[0].indent == 0);
    check_span(comments[0].author, "rndm000nickname");
    check_plain(comments[0].date, "4 \xd1\x87\xd0\xb0\xd1\x81\xd0\xb0 \xd0\xbd\xd0\xb0\xd0\xb7\xd0\xb0\xd0\xb4");
    check_plain(comments[0].body,
        "\xd0\x92 \xd1\x81\xd0\xb5\xd0\xba\xd1\x80\xd0\xb5\xd1\x82\xd0\xbd\xd1\x8b\xd1\x85 "
        "\xd0\xbc\xd0\xb0\xd1\x82\xd0\xb5\xd1\x80\xd0\xb8\xd0\xb0\xd0\xbb\xd0\xb0\xd1\x85 "
        "\xd1\x82\xd0\xb0\xd0\xba\xd0\xb0\xd1\x8f \xd0\xb1\xd1\x8b\xd0\xbb\xd0\xb0 \xd0\xb0\xd0\xb6 11 "
        "\xd1\x81\xd0\xb5\xd0\xb7\xd0\xbe\xd0\xbd\xd0\xbe\xd0\xb2. \xd0\x94\xd0\xb0, "
        "\xd0\xb8\xd1\x81\xd1\x82\xd0\xbe\xd1\x80\xd0\xb8\xd1\x8f "
        "\xd0\x9c\xd0\xb0\xd0\xbb\xd0\xb4\xd0\xb5\xd1\x80\xd0\xb0 \xd0\xb1\xd1\x8b\xd0\xbb\xd0\xb0 "
        "\xd0\xbd\xd0\xb0 \xd0\xbf\xd0\xb5\xd1\x80\xd0\xb2\xd0\xbe\xd0\xbc "
        "\xd0\xbf\xd0\xbb\xd0\xb0\xd0\xbd\xd0\xb5, \xd0\xbd\xd0\xbe \xd0\xbe\xd0\xbd "
        "\xd0\xbd\xd0\xb0 \xd1\x84\xd0\xbe\xd0\xbd\xd0\xb5 "
        "\xd0\xa1\xd0\xba\xd0\xb0\xd0\xbb\xd0\xbb\xd0\xb8 "
        "\xd0\xb2\xd0\xb5\xd1\x87\xd0\xbd\xd0\xbe "
        "\xd0\xbf\xd1\x80\xd0\xb8\xd0\xb4\xd1\x83\xd1\x80\xd0\xba\xd0\xbe\xd0\xbc "
        "\xd0\xb1\xd1\x8b\xd0\xbb.)");
    /* the header avatar is an <img> and must not become media, the commenter's own is the one inside the name link */
    assert(comments[0].media_url.length == 0);
    check_span(comments[0].avatar_url, "https://cs13.pikabu.ru/avatars/1573/l1573995-1120593966.png");
    {
        pk_reaction reactions[PK_REACTIONS_MAX];
        size_t reaction_count = pk_reactions_parse(&doc, comments[0].reactions, reactions, PK_REACTIONS_MAX);
        assert(reaction_count > 0);
        assert(reactions[0].id == 15 && reactions[0].count == 39);
    }

    load(pk_fixture_comment_2);
    count = pk_comments_parse(&doc, comments, 8);
    assert(count == 1);
    assert(comments[0].comment_id.length > 0);
    assert(comments[0].author.length > 0);
    assert(comments[0].body.length > 0);
}

static void test_synthetic_shapes(void) {
    pk_comment comments[8];
    size_t count;

    /* a reply nested inside its parent is still its own comment */
    load("<div class=\"comment\" data-id=\"1\" data-meta=\"pid=0;de=0\">"
         "<div class=\"comment__content\">parent</div>"
         "<div class=\"comment\" data-id=\"2\" data-meta=\"pid=1;de=1\">"
         "<div class=\"comment__content\">child</div></div></div>");
    count = pk_comments_parse(&doc, comments, 8);
    assert(count == 2);
    check_span(comments[0].comment_id, "1");
    assert(comments[0].indent == 0);
    check_span(comments[1].comment_id, "2");
    check_span(comments[1].parent_id, "1");
    assert(comments[1].indent == 1);

    /* a reply's reaction bar sits inside the parent element, and must not be
       read as the parent's own */
    load("<div class=\"comment\" data-id=\"1\">"
         "<div class=\"comment__body\"><div class=\"comment__content\">parent</div>"
         "<div class=\"comment__emotions\">"
         "<button data-id=\"15\" data-count=\"2\" class=\"emotion-btn\">a</button></div></div>"
         "<div class=\"comment\" data-id=\"2\">"
         "<div class=\"comment__body\"><div class=\"comment__content\">child</div>"
         "<div class=\"comment__emotions\">"
         "<button data-id=\"1\" data-count=\"9\" class=\"emotion-btn\">b</button></div></div></div></div>");
    count = pk_comments_parse(&doc, comments, 8);
    assert(count == 2);
    {
        pk_reaction reactions[PK_REACTIONS_MAX];
        assert(pk_reactions_parse(&doc, comments[0].reactions, reactions, PK_REACTIONS_MAX) == 1);
        assert(reactions[0].id == 15 && reactions[0].count == 2);
        assert(pk_reactions_parse(&doc, comments[1].reactions, reactions, PK_REACTIONS_MAX) == 1);
        assert(reactions[0].id == 1 && reactions[0].count == 9);
    }

    /* a deleted comment has no content element and nothing to render */
    load("<div class=\"comment\" data-id=\"9\"><div class=\"comment__hidden\">x</div></div>");
    assert(pk_comments_parse(&doc, comments, 8) == 0);

    /* data-indent is the fallback when data-meta carries no depth */
    load("<div class=\"comment\" data-id=\"3\" data-indent=\"4\">"
         "<div class=\"comment__content\">t</div></div>");
    assert(pk_comments_parse(&doc, comments, 8) == 1);
    assert(comments[0].indent == 4);

    /* a viewable image in the body is media, and a sticker is flagged as one */
    load("<div class=\"comment\" data-id=\"5\"><div class=\"comment__content\">t"
         "<img data-viewable=\"true\" data-large-image=\"/a.jpg\" src=\"/s.jpg\"></div></div>");
    assert(pk_comments_parse(&doc, comments, 8) == 1);
    check_span(comments[0].media_url, "/a.jpg");
    assert(!comments[0].media_is_sticker);

    load("<div class=\"comment\" data-id=\"6\"><div class=\"comment__content\">t"
         "<img class=\"comment__sticker\" src=\"/st.png\"></div></div>");
    assert(pk_comments_parse(&doc, comments, 8) == 1);
    check_span(comments[0].media_url, "/st.png");
    assert(comments[0].media_is_sticker);

    /* the rating is read as a number, negative included */
    load("<div class=\"comment\" data-id=\"7\"><div class=\"comment__content\">t</div>"
         "<span class=\"comment__rating-count\">-14</span></div>");
    assert(pk_comments_parse(&doc, comments, 8) == 1);
    assert(comments[0].score_known && comments[0].score == -14);
    load("<div class=\"comment\" data-id=\"10\"><div class=\"comment__content\">t</div>"
         "<span class=\"comment__rating-count\">&minus;1,2K</span></div>");
    assert(pk_comments_parse(&doc, comments, 8) == 1);
    assert(comments[0].score_known && comments[0].score == -1200);
    load("<div class=\"comment\" data-id=\"8\"><div class=\"comment__body\"><div class=\"comment__content\">t</div>"
         "<div class=\"comment__rating\" aria-label=\"5 plus / 12 minus\"><div class=\"comment__rating-count\"><svg></svg></div></div></div></div>");
    assert(pk_comments_parse(&doc, comments, 8) == 1);
    assert(comments[0].score_known && comments[0].score == -7);
    load("<div class=\"comment\" data-id=\"9\"><div class=\"comment__body\"><div class=\"comment__content\">t</div>"
         "<div class=\"comment__rating\" aria-label=\"rating pending\"><div class=\"comment__rating-count\"><svg></svg></div></div></div></div>");
    assert(pk_comments_parse(&doc, comments, 8) == 1);
    assert(!comments[0].score_known && !comments[0].score_hidden);
    load("<div class=\"comment\" data-id=\"11\"><div class=\"comment__body\"><div class=\"comment__content\">t</div>"
         "<div class=\"comment__rating\" aria-label=\"Низкий рейтинг\"><div class=\"comment__rating-count\"><progress value=\"0.33\"></progress></div></div></div></div>");
    assert(pk_comments_parse(&doc, comments, 8) == 1);
    assert(!comments[0].score_known && comments[0].score_hidden);

    /* the class has to be a whole token, or comment__body counts as a comment */
    load("<div class=\"comment__body\"><div class=\"comment__content\">t</div></div>");
    assert(pk_comments_parse(&doc, comments, 8) == 0);
}

static void test_tree_ids(void) {
    long ids[PK_COMMENTS_MAX];
    size_t count;

    load(pk_fixture_comments_tree);
    count = pk_comments_tree_ids(&doc, ids, PK_COMMENTS_MAX);
    /* the real page has far more ids than the app asks for, so the cap stops the request list and not the
       end of the tree */
    assert(count == PK_COMMENTS_MAX);
    /* every id is the shared minimum plus its own offset */
    assert(ids[0] == 404058478 + 4694);
    assert(ids[1] == 404058478 + 11015);

    load("<script data-entry=\"comments-tree\">{\"min\":100,\"tree\":[[1,0],[2,0,[[3,0]]]]}</script>");
    count = pk_comments_tree_ids(&doc, ids, PK_COMMENTS_MAX);
    assert(count == 3);
    assert(ids[0] == 101 && ids[1] == 102 && ids[2] == 103);

    load("<script data-entry=\"comments-tree\">{\"min\":100,\"tree\":[]}</script>");
    assert(pk_comments_tree_ids(&doc, ids, PK_COMMENTS_MAX) == 0);

    /* a tree that does not parse whole has ids nobody should trust */
    load("<script data-entry=\"comments-tree\">{\"min\":100,\"tree\":[[1,0]</script>");
    assert(pk_comments_tree_ids(&doc, ids, PK_COMMENTS_MAX) == 0);
    load("<script data-entry=\"comments-tree\">{\"min\":\"x\",\"tree\":[[1,0]]}</script>");
    assert(pk_comments_tree_ids(&doc, ids, PK_COMMENTS_MAX) == 0);
    load("<script data-entry=\"comments-tree\">not json at all</script>");
    assert(pk_comments_tree_ids(&doc, ids, PK_COMMENTS_MAX) == 0);
    load("<script data-entry=\"other\">{\"min\":1,\"tree\":[[1,0]]}</script>");
    assert(pk_comments_tree_ids(&doc, ids, PK_COMMENTS_MAX) == 0);
    load("<div>no script here</div>");
    assert(pk_comments_tree_ids(&doc, ids, PK_COMMENTS_MAX) == 0);

    /* an offset that lands on or below zero is not an id pikabu issued */
    load("<script data-entry=\"comments-tree\">{\"min\":5,\"tree\":[[-5,0],[1,0]]}</script>");
    assert(pk_comments_tree_ids(&doc, ids, PK_COMMENTS_MAX) == 1);
    assert(ids[0] == 6);
}

int main(void) {
    test_real_comment();
    test_synthetic_shapes();
    test_tree_ids();
    return 0;
}
