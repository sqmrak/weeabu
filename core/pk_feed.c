#include "pk_feed.h"

#include <string.h>

#include "pk_text.h"

/* the lazy loader keeps the real file in a data attribute and a placeholder in src */
static const char *const pk_image_attributes[] = {
    "data-large-image", "data-src", "data-original", "src"
};
static const char *const pk_poster_attributes[] = {
    "poster", "data-poster", "data-thumbnail-url"
};

#define PK_COUNT_OF(array) (sizeof(array) / sizeof((array)[0]))

static int pk_feed_is_ad(const pk_html *doc, pk_span article) {
    pk_span value;
    if (pk_html_has_class(doc, article, "story-promo") ||
        pk_html_has_class(doc, article, "story_ad") ||
        pk_html_has_class(doc, article, "native-ad")) return 1;
    if (pk_html_attr(doc, article, "data-ad", &value) == PK_OK ||
        pk_html_attr(doc, article, "data-advert", &value) == PK_OK ||
        pk_html_attr(doc, article, "data-promo", &value) == PK_OK) return 1;
    return 0;
}

/* the live feed marks a paid card with a story__sponsor link and data-ca="1" on the article */
static int pk_feed_is_sponsored(const pk_html *doc, pk_span article, pk_span card) {
    pk_span tag;
    pk_span value;
    if (pk_html_attr(doc, article, "data-ca", &value) == PK_OK && value.length == 1 && doc->data[value.offset] == '1') return 1;
    return pk_html_find_in(doc, card, "a", "story__sponsor", &tag) == PK_OK;
}

/* the rendered text rounds to "5.7K", so it is only the fallback */
static int pk_feed_attr_number(const pk_html *doc, pk_span tag, const char *name, long *value) {
    pk_span raw;
    long parsed = 0;
    if (pk_html_attr(doc, tag, name, &raw) != PK_OK || !raw.length) return 0;
    if (pk_number_compact(doc->data + raw.offset, raw.length, &parsed) != PK_OK) return 0;
    *value = parsed;
    return 1;
}

/* a missing element leaves the value alone */
static int pk_feed_count(const pk_html *doc, pk_span range, const char *name, const char *cls, long *value) {
    pk_span tag;
    pk_span body;
    char text[64];
    size_t written = 0;
    long parsed = 0;
    if (pk_html_find_in(doc, range, name, cls, &tag) != PK_OK) return 0;
    if (pk_html_body(doc, tag, &body) != PK_OK || !body.length) return 0;
    if (pk_text_plain(doc->data + body.offset, body.length, text, sizeof(text), &written) != PK_OK) return 0;
    if (pk_number_compact(text, written, &parsed) != PK_OK) return 0;
    *value = parsed;
    return 1;
}

/* a card that hides its rating still says "221 плюс / 57 минусов" */
static int pk_feed_rating_label(const pk_html *doc, pk_span range, long *value) {
    pk_span block;
    pk_span label;
    if (pk_html_find_in(doc, range, "div", "story__rating-block", &block) != PK_OK) return 0;
    if (pk_html_attr(doc, block, "aria-label", &label) != PK_OK) return 0;
    return pk_rating_label(doc->data + label.offset, label.length, value);
}

static void pk_feed_tags(const pk_html *doc, pk_span range, pk_post *post) {
    size_t from = range.offset;
    size_t limit = range.offset + range.length;
    size_t visited = 0;
    post->tag_count = 0;
    while (post->tag_count < PK_POST_MAX_TAGS && from < limit && visited++ < PK_FEED_MAX_POSTS * 8) {
        pk_span tag;
        pk_span body;
        char text[128];
        size_t written = 0;
        pk_span remaining;
        remaining.offset = from;
        remaining.length = limit - from;
        if (pk_html_find_in(doc, remaining, "a", "tags__tag", &tag) != PK_OK) return;
        from = tag.offset + tag.length;
        if (pk_html_body(doc, tag, &body) != PK_OK || !body.length) continue;
        if (pk_text_plain(doc->data + body.offset, body.length, text, sizeof(text), &written) != PK_OK) continue;
        /* the "+3" counter at the end of the tag row is not a tag */
        if (!written || pk_text_is_count_label(text, written)) continue;
        post->tags[post->tag_count++] = body;
    }
}

static void pk_feed_image(const pk_html *doc, pk_span range, pk_post *post) {
    pk_span tag;
    pk_span block;
    if (pk_html_find_in(doc, range, "img", "story-image__image", &tag) == PK_OK &&
        pk_html_attr_any(doc, tag, pk_image_attributes, PK_COUNT_OF(pk_image_attributes), &post->image_url) == PK_OK)
        return;
    if (pk_html_find_in(doc, range, "video", NULL, &tag) == PK_OK &&
        pk_html_attr_any(doc, tag, pk_poster_attributes, PK_COUNT_OF(pk_poster_attributes), &post->image_url) == PK_OK)
        return;
    /* stay inside the block: the first img of a text-only card is the avatar */
    if (pk_html_find_in(doc, range, "div", "story-block_type_image", &block) == PK_OK) {
        pk_span body;
        if (pk_html_body(doc, block, &body) != PK_ERR_INVALID &&
            pk_html_find_in(doc, body, "img", NULL, &tag) == PK_OK)
            pk_html_attr_any(doc, tag, pk_image_attributes, PK_COUNT_OF(pk_image_attributes), &post->image_url);
    }
}

static void pk_feed_avatar(const pk_html *doc, pk_span range, pk_post *post) {
    pk_span link;
    pk_span body;
    pk_span tag;
    if (pk_html_find_in(doc, range, "a", "story__user-link", &link) != PK_OK) return;
    if (pk_html_body(doc, link, &body) == PK_ERR_INVALID || !body.length) return;
    if (pk_html_find_in(doc, body, "img", NULL, &tag) != PK_OK) return;
    pk_html_attr_any(doc, tag, pk_image_attributes, PK_COUNT_OF(pk_image_attributes), &post->avatar_url);
}

static void pk_feed_community(const pk_html *doc, pk_span range, pk_post *post) {
    pk_span tag;
    pk_span body;
    if (pk_html_find_in(doc, range, "span", "story__community-name", &tag) != PK_OK) return;
    if (pk_html_body(doc, tag, &body) == PK_OK && body.length) post->community = body;
}

/* content-inner also holds the video player, whose "Перейти к видео" controls would read as post text */
static void pk_feed_excerpt(const pk_html *doc, pk_span card, pk_post *post) {
    pk_span content;
    pk_span inner;
    pk_span block;
    pk_span body;
    if (pk_html_find_in(doc, card, "div", "story__content-inner", &content) != PK_OK ||
        pk_html_body(doc, content, &inner) == PK_ERR_INVALID) return;
    if (pk_html_find_in(doc, inner, "div", "story-block_type_text", &block) == PK_OK) {
        if (pk_html_body(doc, block, &body) != PK_ERR_INVALID) post->excerpt = body;
        return;
    }
    if (pk_html_find_in(doc, inner, "div", "story-block", &block) != PK_OK) post->excerpt = inner;
}

static void pk_feed_media_size(const pk_html *doc, pk_span block_body, pk_block_type type, pk_post *post) {
    pk_span tag;
    pk_span value;
    long width = 0;
    long height = 0;
    if (post->media_count != 1) return;
    if (type == PK_BLOCK_IMAGE) {
        if (pk_html_find_in(doc, block_body, "svg", "story-image__stretch", &tag) == PK_OK &&
            pk_html_attr(doc, tag, "viewBox", &value) == PK_OK &&
            pk_story_view_box(doc->data + value.offset, value.length, &width, &height)) {
            post->media_width = width;
            post->media_height = height;
        }
        return;
    }
    if (pk_html_find_in(doc, block_body, "video", NULL, &tag) == PK_OK &&
        pk_feed_attr_number(doc, tag, "data-width", &width) &&
        pk_feed_attr_number(doc, tag, "data-height", &height) && width > 0 && height > 0) {
        post->media_width = width;
        post->media_height = height;
    }
}

/* a block the card cannot show, like the player control row, adds nothing */
static void pk_feed_blocks(const pk_html *doc, pk_span card, pk_post *post) {
    pk_span content;
    pk_span inner;
    pk_span hidden;
    size_t hidden_offset;
    size_t cursor;
    size_t limit;
    size_t visited = 0;
    if (pk_html_find_in(doc, card, "div", "story__content-inner", &content) != PK_OK ||
        pk_html_body(doc, content, &inner) == PK_ERR_INVALID) return;
    post->has_hidden = pk_html_find_in(doc, inner, "div", "story__hidden-blocks", &hidden) == PK_OK;
    hidden_offset = post->has_hidden ? hidden.offset : inner.offset + inner.length;
    cursor = inner.offset;
    limit = inner.offset + inner.length;
    while (cursor < limit && visited++ < PK_STORY_MAX_BLOCKS) {
        pk_span range;
        pk_span block;
        pk_span body;
        range.offset = cursor;
        range.length = limit - cursor;
        if (pk_html_find_in(doc, range, "div", "story-block", &block) != PK_OK) break;
        if (pk_html_body(doc, block, &body) == PK_ERR_INVALID) break;
        cursor = body.offset + body.length;
        if (pk_html_has_class(doc, block, "story-block_type_text")) {
            if (post->text_count >= PK_POST_MAX_TEXT) continue;
            post->text_blocks[post->text_count++] = body;
            if (block.offset < hidden_offset) post->text_visible_count = post->text_count;
        } else if (pk_html_has_class(doc, block, "story-block_type_image") ||
                   pk_html_has_class(doc, block, "story-block_type_video")) {
            pk_story_block parts[4];
            size_t found = pk_story_blocks(doc, body, parts, 4);
            size_t index;
            for (index = 0; index < found; index++) {
                pk_post_media *media;
                if (parts[index].type == PK_BLOCK_TEXT || post->media_count >= PK_POST_MAX_MEDIA) continue;
                media = &post->media[post->media_count++];
                media->type = parts[index].type;
                media->url = parts[index].url;
                media->poster = parts[index].poster;
                media->duration = parts[index].duration;
                pk_feed_media_size(doc, body, parts[index].type, post);
                break;
            }
        }
    }
    if (!post->text_count && post->excerpt.length) {
        post->text_blocks[0] = post->excerpt;
        post->text_count = 1;
        post->text_visible_count = 1;
    }
}

static void pk_feed_parent(const pk_html *doc, pk_span range, pk_post *post) {
    pk_span tag;
    if (pk_html_find_in(doc, range, "a", "story__parent-link", &tag) != PK_OK) return;
    if (pk_html_attr(doc, tag, "href", &post->parent_url) != PK_OK || !post->parent_url.length) {
        post->parent_url = PK_SPAN_NONE;
        return;
    }
    pk_html_attr(doc, tag, "title", &post->parent_title);
}

static void pk_feed_date(const pk_html *doc, pk_span range, pk_post *post) {
    pk_span tag;
    pk_span body;
    if (pk_html_find_in(doc, range, "time", "story__datetime", &tag) != PK_OK) return;
    if (pk_html_body(doc, tag, &body) == PK_OK && body.length) {
        post->date = body;
        return;
    }
    /* an empty <time> still carries the machine readable form */
    pk_html_attr(doc, tag, "datetime", &post->date);
}

static int pk_feed_card(const pk_html *doc, pk_span card, pk_span article_tag, pk_post *post) {
    pk_span tag;
    pk_span body;

    memset(post, 0, sizeof(*post));
    post->url = PK_SPAN_NONE;
    post->title = PK_SPAN_NONE;

    if (pk_html_find_in(doc, card, "a", "story__title-link", &tag) != PK_OK) return 0;
    if (pk_html_attr(doc, tag, "href", &post->url) != PK_OK || !post->url.length) return 0;

    /* the <h2> also holds the hidden-post badge and the reply counter, which would end up in the title */
    if (pk_html_body(doc, tag, &body) == PK_OK && body.length) {
        post->title = body;
    } else {
        if (pk_html_find_in(doc, card, "h2", "story__title", &tag) != PK_OK) return 0;
        if (pk_html_body(doc, tag, &body) != PK_OK || !body.length) return 0;
        post->title = body;
    }

    pk_html_attr(doc, article_tag, "data-story-id", &post->story_id);
    if (pk_html_find_in(doc, card, "a", "story__user-link", &tag) != PK_OK ||
        pk_html_attr(doc, tag, "data-name", &post->author) != PK_OK)
        pk_html_attr(doc, article_tag, "data-author-name", &post->author);

    post->score_known = pk_feed_attr_number(doc, article_tag, "data-rating", &post->score) ||
        pk_feed_count(doc, card, "div", "story__rating-count", &post->score) ||
        pk_feed_rating_label(doc, card, &post->score);
    if (pk_html_find_in(doc, card, "div", "story__emotions", &tag) == PK_OK)
        pk_html_body(doc, tag, &post->reactions);
    if (!pk_feed_attr_number(doc, article_tag, "data-comments", &post->comments))
        pk_feed_count(doc, card, "span", "story__comments-link-count-inner", &post->comments);
    pk_feed_image(doc, card, post);
    pk_feed_avatar(doc, card, post);
    pk_feed_community(doc, card, post);
    pk_feed_date(doc, card, post);
    pk_feed_excerpt(doc, card, post);
    pk_feed_blocks(doc, card, post);
    pk_feed_parent(doc, card, post);

    {
        pk_span container;
        if (pk_html_find_in(doc, card, "div", "collapsed-tags-container", &container) == PK_OK ||
            pk_html_find_in(doc, card, "div", "tags", &container) == PK_OK) {
            pk_span inner;
            if (pk_html_body(doc, container, &inner) == PK_OK) pk_feed_tags(doc, inner, post);
        }
    }

    post->has_video = pk_html_find_in(doc, card, "video", NULL, &tag) == PK_OK ||
                      pk_html_find_in(doc, card, "div", "story-block_type_video", &tag) == PK_OK;
    return 1;
}

size_t pk_feed_parse(const pk_html *doc, pk_post *posts, size_t capacity) {
    size_t count = 0;
    size_t from = 0;
    size_t visited = 0;
    if (!doc || !doc->data || !posts || !capacity) return 0;
    if (capacity > PK_FEED_MAX_POSTS) capacity = PK_FEED_MAX_POSTS;

    while (count < capacity && from < doc->length && visited++ < PK_FEED_MAX_POSTS * 4) {
        pk_span article;
        pk_span card;
        if (pk_html_find(doc, from, "article", "story", &article) != PK_OK) break;
        from = article.offset + article.length;
        if (pk_feed_is_ad(doc, article)) continue;
        /* a page cut mid-card still describes a real post */
        if (pk_html_body(doc, article, &card) == PK_ERR_INVALID) continue;
        if (!card.length) continue;
        if (pk_feed_is_sponsored(doc, article, card)) {
            from = card.offset + card.length;
            continue;
        }
        if (pk_feed_card(doc, card, article, &posts[count])) count++;
        from = card.offset + card.length;
    }
    return count;
}
