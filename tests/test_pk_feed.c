#include <assert.h>
#include <stdio.h>
#include <string.h>

#include "pk_feed.h"
#include "pk_story.h"
#include "pk_text.h"
#include "pk_url.h"

#include "feed_fixture.inc"
#include "feed_cards_fixture.inc"

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

static void test_real_card(void) {
    pk_post posts[PK_FEED_MAX_POSTS];
    size_t count;
    char url[PK_MAX_URL_BYTES];

    load(pk_fixture_card);
    count = pk_feed_parse(&doc, posts, PK_FEED_MAX_POSTS);
    assert(count == 1);

    check_span(posts[0].story_id, "14318363");
    check_span(posts[0].url, "https://pikabu.ru/story/tru_stori_14318363");
    assert(pk_url_normalize(doc.data + posts[0].url.offset, posts[0].url.length, url, sizeof(url), NULL) == PK_OK);
    assert(!strcmp(url, "https://pikabu.ru/story/tru_stori_14318363"));

    /* the title is the link text alone: the reply-stories counter that sits in
       the same <h2> must not end up appended to it */
    check_plain(posts[0].title, "\xd0\xa2\xd1\x80\xd1\x83 \xd1\x81\xd1\x82\xd0\xbe\xd1\x80\xd0\xb8");
    check_span(posts[0].author, "Fresh4MaN");

    /* the article's own data-rating wins over the rounded "5.7K" it renders */
    assert(posts[0].score == 5692);
    assert(posts[0].comments == 678);

    /* the svg icon inside <time> is markup, not part of the date */
    check_plain(posts[0].date, "6 \xd1\x87\xd0\xb0\xd1\x81\xd0\xbe\xd0\xb2 \xd0\xbd\xd0\xb0\xd0\xb7\xd0\xb0\xd0\xb4");

    check_span(posts[0].image_url, "https://cs4.pikabu.ru/s/2026/09/10/06/ylnl7cmk.jpg");
    assert(!posts[0].has_video);
    /* an image-only card has no text to excerpt */
    assert(posts[0].excerpt.length == 0);
    check_span(posts[0].avatar_url, "https://cs6.pikabu.ru/avatars/518/m518206-1555465616.jpg");

    /* the card carries eight tags and the cell shows the first four */
    assert(posts[0].tag_count == PK_POST_MAX_TAGS);
    check_plain(posts[0].tags[0], "Threads");
    check_plain(posts[0].tags[1], "\xd0\xa4\xd0\xb8\xd0\xbb\xd1\x8c\xd0\xbc\xd1\x8b");
}

static void test_minimal_card(void) {
    pk_post posts[PK_FEED_MAX_POSTS];
    size_t count;

    load("<article class=\"story\" data-story-id=\"7\">"
         "<h2 class=\"story__title\"><a class=\"story__title-link\" href=\"/story/x_7\">Title</a></h2>"
         "</article>");
    count = pk_feed_parse(&doc, posts, PK_FEED_MAX_POSTS);
    assert(count == 1);
    check_span(posts[0].url, "/story/x_7");
    check_plain(posts[0].title, "Title");
    /* a card that carries nothing else reports nothing else */
    assert(posts[0].author.length == 0);
    assert(posts[0].image_url.length == 0);
    assert(posts[0].tag_count == 0);
    assert(posts[0].score == 0 && posts[0].comments == 0);
    assert(posts[0].excerpt.length == 0);
}

static void test_cards_are_skipped_not_half_built(void) {
    pk_post posts[PK_FEED_MAX_POSTS];

    /* no link means neither the list nor the detail screen can use the card */
    load("<article class=\"story\"><h2 class=\"story__title\">no link</h2></article>");
    assert(pk_feed_parse(&doc, posts, PK_FEED_MAX_POSTS) == 0);

    /* an empty link text falls back to the heading around it */
    load("<article class=\"story\">"
         "<h2 class=\"story__title\"><a class=\"story__title-link\" href=\"/a\"></a>fallback</h2>"
         "</article>");
    assert(pk_feed_parse(&doc, posts, PK_FEED_MAX_POSTS) == 1);
    check_plain(posts[0].title, "fallback");

    /* the class is a whole token, so a promo block is not a post card */
    load("<article class=\"story-promo\"><a class=\"story__title-link\" href=\"/a\">x</a></article>");
    assert(pk_feed_parse(&doc, posts, PK_FEED_MAX_POSTS) == 0);
    load("<article class=\"story\" data-ad=\"1\"><a class=\"story__title-link\" href=\"/a\">x</a></article>");
    assert(pk_feed_parse(&doc, posts, PK_FEED_MAX_POSTS) == 0);
}

static void test_several_cards(void) {
    pk_post posts[PK_FEED_MAX_POSTS];
    size_t count;
    load("<article class=\"story\" data-story-id=\"1\">"
         "<a class=\"story__title-link\" href=\"/a\">first</a></article>"
         "<article class=\"story\" data-story-id=\"2\">"
         "<a class=\"story__title-link\" href=\"/b\">second</a></article>"
         "<article class=\"story\" data-story-id=\"3\">"
         "<a class=\"story__title-link\" href=\"/c\">third</a></article>");
    count = pk_feed_parse(&doc, posts, PK_FEED_MAX_POSTS);
    assert(count == 3);
    check_span(posts[0].story_id, "1");
    check_span(posts[2].story_id, "3");
    /* each card reads only its own markup, never the next one down the page */
    check_span(posts[0].url, "/a");
    check_span(posts[1].url, "/b");
    check_span(posts[2].url, "/c");

    /* the caller's array is the ceiling */
    count = pk_feed_parse(&doc, posts, 2);
    assert(count == 2);
}

static void test_video_card(void) {
    pk_post posts[PK_FEED_MAX_POSTS];
    load("<article class=\"story\">"
         "<a class=\"story__title-link\" href=\"/v\">clip</a>"
         "<div class=\"story-block story-block_type_video\">"
         "<video poster=\"/still.jpg\"><source src=\"/v.mp4\"></video></div></article>");
    assert(pk_feed_parse(&doc, posts, PK_FEED_MAX_POSTS) == 1);
    assert(posts[0].has_video);
    /* the list shows the still frame, the player fetches the file later */
    check_span(posts[0].image_url, "/still.jpg");
}

static void test_bounds(void) {
    pk_post posts[PK_FEED_MAX_POSTS];
    load("");
    assert(pk_feed_parse(&doc, posts, PK_FEED_MAX_POSTS) == 0);
    load("<article class=\"story\"><a class=\"story__title-link\" href=\"/a\">x</a>");
    /* a page cut off mid card still describes a real post */
    assert(pk_feed_parse(&doc, posts, PK_FEED_MAX_POSTS) == 1);
    load("<article class=\"story\"></article>");
    assert(pk_feed_parse(&doc, posts, PK_FEED_MAX_POSTS) == 0);
    assert(pk_feed_parse(&doc, posts, 0) == 0);
    assert(pk_feed_parse(&doc, NULL, PK_FEED_MAX_POSTS) == 0);
}


static pk_post parse_one(const char *html) {
    pk_post posts[PK_FEED_MAX_POSTS];
    load(html);
    assert(pk_feed_parse(&doc, posts, PK_FEED_MAX_POSTS) == 1);
    return posts[0];
}

/* a text-only post has no preview, the first img is the avatar, which used to show as the post picture */
static void test_text_card_has_no_preview(void) {
    pk_post post = parse_one(pk_fixture_text_card);
    check_span(post.story_id, "14387978");
    assert(post.image_url.length == 0);
    check_span(post.avatar_url, "https://cs13.pikabu.ru/avatars/2255/m2255713-1640713767.png");
    check_span(post.author, "SergNick");
    check_plain(post.community, "\xd0\xae\xd0\xbc\xd0\xbe\xd1\x80 \xd0\xb4\xd0\xbb\xd1\x8f \xd0\xb2\xd1\x81\xd0\xb5\xd1\x85 \xd0\xb8 \xd0\xba\xd0\xb0\xd0\xb6\xd0\xb4\xd0\xbe\xd0\xb3\xd0\xbe");
    assert(post.score == 5145);
    assert(post.comments == 630);
    assert(post.excerpt.length > 0);
}

/* the card labels the rating only as "221 плюс / 57 минусов", which used to show as 0 */
static void test_hidden_rating_comes_from_the_label(void) {
    pk_post post = parse_one(pk_fixture_hidden_rating_card);
    check_span(post.story_id, "14385636");
    assert(post.score_known && post.score == 164);
    assert(post.comments == 84);
}

static void test_rating_sources_in_order(void) {
    pk_post post;
    /* the attribute is exact, the text is rounded, the label is the last resort */
    post = parse_one("<article class=\"story\" data-rating=\"1234\" data-comments=\"56\">"
                     "<a class=\"story__title-link\" href=\"/a\">t</a>"
                     "<div class=\"story__rating-count\">1.2K</div>"
                     "<span class=\"story__comments-link-count-inner\">9</span></article>");
    assert(post.score == 1234 && post.comments == 56);
    post = parse_one("<article class=\"story\"><a class=\"story__title-link\" href=\"/a\">t</a>"
                     "<div class=\"story__rating-count\">1.2K</div>"
                     "<span class=\"story__comments-link-count-inner\">9</span></article>");
    assert(post.score == 1200 && post.comments == 9);
    post = parse_one("<article class=\"story\"><a class=\"story__title-link\" href=\"/a\">t</a>"
                     "<div class=\"story__rating-block\" aria-label=\"5 plus / 12 minus\"></div></article>");
    assert(post.score_known && post.score == -7);
    /* a label with one number is not a rating */
    post = parse_one("<article class=\"story\"><a class=\"story__title-link\" href=\"/a\">t</a>"
                     "<div class=\"story__rating-block\" aria-label=\"rating hidden 5\"></div></article>");
    assert(!post.score_known && post.score == 0);
    /* the site hides new post ratings behind an svg rather than a zero */
    post = parse_one("<article class=\"story\"><a class=\"story__title-link\" href=\"/a\">t</a>"
                     "<div class=\"story__rating-block\" aria-label=\"rating pending\"><div class=\"story__rating-count\"><svg></svg></div></div></article>");
    assert(!post.score_known);
    /* a real zero is distinct from the pending icon */
    post = parse_one("<article class=\"story\" data-rating=\"-42\"><a class=\"story__title-link\" href=\"/a\">t</a></article>");
    assert(post.score_known && post.score == -42);
    post = parse_one("<article class=\"story\" data-rating=\"0\"><a class=\"story__title-link\" href=\"/a\">t</a></article>");
    assert(post.score_known && post.score == 0);
    post = parse_one("<article class=\"story\"><a class=\"story__title-link\" href=\"/a\">t</a>"
                     "<div class=\"story__emotions\"><button class=\"emotion-btn\" data-id=\"15\" data-count=\"3\"></button></div></article>");
    assert(post.reactions.length > 0);
    {
        pk_reaction reactions[4];
        size_t count = pk_reactions_parse(&doc, post.reactions, reactions, 4);
        assert(count == 1 && reactions[0].id == 15 && reactions[0].count == 3);
    }
    /* a number past any real score is refused instead of wrapping */
    post = parse_one("<article class=\"story\"><a class=\"story__title-link\" href=\"/a\">t</a>"
                     "<div class=\"story__rating-block\" aria-label=\"99999999999999999999 / 1\"></div></article>");
    assert(!post.score_known && post.score == 0);
}

/* the body of a video card also carries the player controls, whose captions
   used to open the excerpt */
static void test_video_excerpt_skips_player_controls(void) {
    pk_post post = parse_one(pk_fixture_video_card);
    char text[2048];
    size_t written = 0;
    assert(post.has_video);
    assert(post.image_url.length > 0);
    assert(post.excerpt.length > 0);
    assert(pk_text_plain(doc.data + post.excerpt.offset, post.excerpt.length, text, sizeof(text), &written) == PK_OK);
    assert(!strstr(text, "\xd0\x9f\xd0\xb5\xd1\x80\xd0\xb5\xd0\xb9\xd1\x82\xd0\xb8 \xd0\xba \xd0\xb2\xd0\xb8\xd0\xb4\xd0\xb5\xd0\xbe"));
    assert(!strstr(text, "\xd0\x91\xd0\xbe\xd0\xbb\xd1\x8c\xd1\x88\xd0\xb5 \xd0\xb2\xd0\xb8\xd0\xb4\xd0\xb5\xd0\xbe"));
}

static void test_default_avatar_is_no_avatar(void) {
    pk_post post = parse_one(pk_fixture_default_avatar_card);
    assert(post.avatar_url.length == 0);
    assert(post.image_url.length > 0);
    assert(post.author.length > 0);
}

/* an advertising slot is an <article class="story"> with an id and no title */
static void test_ad_slot_is_not_a_post(void) {
    pk_post posts[PK_FEED_MAX_POSTS];
    load(pk_fixture_ad_card);
    assert(pk_feed_parse(&doc, posts, PK_FEED_MAX_POSTS) == 0);
}

/* the byline falls back to the article's own attribute when the link has none */
static void test_author_falls_back_to_article(void) {
    pk_post post = parse_one("<article class=\"story\" data-author-name=\"Nick\">"
                             "<a class=\"story__title-link\" href=\"/a\">t</a></article>");
    check_span(post.author, "Nick");
}

/* the avatar is read from the user link alone, never from the post body */
static void test_avatar_is_scoped_to_the_user_link(void) {
    pk_post post = parse_one("<article class=\"story\">"
                             "<a class=\"story__title-link\" href=\"/a\">t</a>"
                             "<div class=\"story-block story-block_type_image\"><img src=\"/pic.jpg\"></div></article>");
    assert(post.avatar_url.length == 0);
    check_span(post.image_url, "/pic.jpg");
}


/* a collapsed card shows the blocks before the cut, the rest appears once expanded */
static void test_text_blocks_split_at_the_cut(void) {
    pk_post post = parse_one(pk_fixture_text_card);
    assert(post.has_hidden);
    assert(post.text_count == 10);
    assert(post.text_visible_count == 4);
    assert(post.media_count == 0);
    check_plain(post.text_blocks[4], "\xd0\x9f\xd1\x80\xd0\xb8\xd0\xb1\xd0\xb5\xd0\xb3\xd0\xb0\xd0\xb5\xd1\x82\x20\xd0\xb5\xd0\xb5\x20\xd0\xbc\xd1\x83\xd0\xb6\xd0\xb8\xd0\xba\x20\xd1\x81\xd1\x82\xd1\x83\xd1\x87\xd0\xb8\xd1\x82\x20\xd0\xb2\x20\xd0\xb4\xd0\xb2\xd0\xb5\xd1\x80\xd1\x8c");
}

/* an image behind the cut still counts, its box is known from the svg placeholder before the picture arrives */
static void test_hidden_image_and_its_box(void) {
    pk_post post = parse_one(pk_fixture_hidden_rating_card);
    assert(post.has_hidden);
    assert(post.text_visible_count == 1);
    assert(post.text_count > 1);
    assert(post.media_count >= 1);
    assert(post.media[0].type == PK_BLOCK_IMAGE);
    check_span(post.media[0].url, "https://cs18.pikabu.ru/s/2026/05/21/18/hpdrffof_lg.png");
    assert(post.media_width == 700 && post.media_height == 490);
}

static void test_video_media_and_box(void) {
    pk_post post = parse_one(pk_fixture_video_card);
    assert(post.media_count == 1);
    assert(post.media[0].type == PK_BLOCK_VIDEO);
    assert(post.media[0].url.length > 0);
    assert(post.media[0].poster.length > 0);
    assert(post.media_width == 480 && post.media_height == 640);
    assert(post.has_hidden);
    assert(post.text_count == 1 && post.text_visible_count == 0);
}

static void test_plain_image_card_has_no_hidden_part(void) {
    pk_post post = parse_one(pk_fixture_default_avatar_card);
    assert(!post.has_hidden);
    assert(post.text_count == 0);
    assert(post.media_count == 1);
    assert(post.media_width == 700 && post.media_height == 431);
}

static void test_media_count_and_bounds(void) {
    static char html[8192];
    size_t used = 0;
    size_t index;
    pk_post post;
    used += (size_t)snprintf(html + used, sizeof(html) - used,
        "<article class=\"story\"><a class=\"story__title-link\" href=\"/story/x_1\">T</a><div class=\"story__content-inner\">");
    for (index = 0; index < PK_POST_MAX_MEDIA + 6; index++)
        used += (size_t)snprintf(html + used, sizeof(html) - used,
            "<div class=\"story-block story-block_type_image\"><figure class=\"story-image\">"
            "<svg class=\"story-image__stretch\" viewBox=\"0 0 %zu 200\"></svg>"
            "<img class=\"story-image__image\" data-src=\"/p%zu.jpg\"></figure></div>", 100 + index, index);
    used += (size_t)snprintf(html + used, sizeof(html) - used, "</div></article>");
    assert(used < sizeof(html));
    post = parse_one(html);
    assert(post.media_count == PK_POST_MAX_MEDIA);
    assert(post.media_width == 100 && post.media_height == 200);
    check_span(post.media[1].url, "/p1.jpg");
}

static void test_bad_view_box_reports_no_box(void) {
    pk_post post = parse_one("<article class=\"story\"><a class=\"story__title-link\" href=\"/story/x_1\">T</a>"
        "<div class=\"story__content-inner\"><div class=\"story-block story-block_type_image\"><figure>"
        "<svg class=\"story-image__stretch\" viewBox=\"0 0 abc 200\"></svg><img class=\"story-image__image\" data-src=\"/a.jpg\"></figure></div></div></article>");
    assert(post.media_count == 1);
    assert(post.media_width == 0 && post.media_height == 0);
}

/* the sponsored card of the live hot feed, cut down to its header: it was listed as an ordinary post */
static const char pk_sponsored_card[] =
    "<article class=\"story\" data-story-id=\"14508316\" data-is-fixed-story=\"true\" data-author-name=\"specials\" data-comments=\"0\" data-ca=\"1\">"
    "<div class=\"story__main\"><header class=\"story__header\"><div class=\"story__labels\">"
    "<a href=\"https://special.pikabu.ru/mediakit?from=ad_unit\" target=\"_blank\" rel=\"nofollow\" class=\"story__sponsor\">\xd0\x9f\xd0\xb0\xd1\x80\xd1\x82\xd0\xbd\xd1\x91\xd1\x80\xd1\x81\xd0\xba\xd0\xb8\xd0\xb9 \xd0\xbc\xd0\xb0\xd1\x82\xd0\xb5\xd1\x80\xd0\xb8\xd0\xb0\xd0\xbb</a>"
    "<span class=\"story__sponsor_disclaimer hidden\">\xd0\xa0\xd0\xb5\xd0\xba\xd0\xbb\xd0\xb0\xd0\xbc\xd0\xb0</span></div>"
    "<h2 class=\"story__title\"><a href=\"https://pikabu.ru/story/kto_ty_v_gta_14508316\" class=\"story__title-link\">GTA</a></h2></header></div></article>";

static void test_sponsored_card_is_not_a_post(void) {
    static char page[16384];
    pk_post posts[PK_FEED_MAX_POSTS];
    snprintf(page, sizeof(page), "%s%s", pk_sponsored_card, pk_fixture_default_avatar_card);
    load(page);
    assert(pk_feed_parse(&doc, posts, PK_FEED_MAX_POSTS) == 1);
    check_span(posts[0].story_id, "14388737");
    /* the marker on the article alone is enough, and a sponsor link alone is too */
    load("<article class=\"story\" data-story-id=\"1\" data-ca=\"1\"><a class=\"story__title-link\" href=\"/story/a_1\">T</a></article>");
    assert(pk_feed_parse(&doc, posts, PK_FEED_MAX_POSTS) == 0);
    load("<article class=\"story\" data-story-id=\"2\"><a class=\"story__sponsor\" href=\"/x\">p</a><a class=\"story__title-link\" href=\"/story/b_2\">T</a></article>");
    assert(pk_feed_parse(&doc, posts, PK_FEED_MAX_POSTS) == 0);
    /* data-ca="0" is not a marker */
    load("<article class=\"story\" data-story-id=\"3\" data-ca=\"0\"><a class=\"story__title-link\" href=\"/story/c_3\">T</a></article>");
    assert(pk_feed_parse(&doc, posts, PK_FEED_MAX_POSTS) == 1);
}

/* a reply post carries the link to the post it answers beside its title */
static void test_reply_post_links_its_parent(void) {
    pk_post post = parse_one(pk_fixture_text_card);
    check_span(post.parent_url, "https://pikabu.ru/story/otvet_na_post_blina_myi_rabotaem_14387896");
    check_plain(post.parent_title, "\xd0\x9e\xd1\x82\xd0\xb2\xd0\xb5\xd1\x82 \xd0\xbd\xd0\xb0 \xd0\xbf\xd0\xbe\xd1\x81\xd1\x82 \xc2\xab\xd0\x91\xd0\xbb\xd0\xb8\xd0\xbd...\xd0\xb0 \xd0\xbc\xd1\x8b \xd1\x80\xd0\xb0\xd0\xb1\xd0\xbe\xd1\x82\xd0\xb0\xd0\xb5\xd0\xbc\xc2\xbb");
    post = parse_one(pk_fixture_default_avatar_card);
    assert(post.parent_url.length == 0 && post.parent_title.length == 0);
}

int main(void) {
    test_real_card();
    test_minimal_card();
    test_cards_are_skipped_not_half_built();
    test_several_cards();
    test_video_card();
    test_bounds();
    test_text_card_has_no_preview();
    test_hidden_rating_comes_from_the_label();
    test_rating_sources_in_order();
    test_video_excerpt_skips_player_controls();
    test_default_avatar_is_no_avatar();
    test_ad_slot_is_not_a_post();
    test_author_falls_back_to_article();
    test_avatar_is_scoped_to_the_user_link();
    test_text_blocks_split_at_the_cut();
    test_hidden_image_and_its_box();
    test_video_media_and_box();
    test_plain_image_card_has_no_hidden_part();
    test_media_count_and_bounds();
    test_bad_view_box_reports_no_box();
    test_sponsored_card_is_not_a_post();
    test_reply_post_links_its_parent();
    return 0;
}
