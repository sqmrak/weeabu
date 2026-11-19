#include "pk_story.h"

#include <string.h>

#include "pk_text.h"

static const char *const pk_story_image_attributes[] = {
    "data-large-image", "data-src", "data-original", "src"
};
static const char *const pk_story_video_attributes[] = {
    "data-source", "data-src", "src"
};
static const char *const pk_story_poster_attributes[] = {
    "poster", "data-poster", "data-thumbnail-url"
};

#define PK_COUNT_OF(array) (sizeof(array) / sizeof((array)[0]))

int pk_story_view_box(const char *text, size_t length, long *width, long *height) {
    long values[4];
    size_t count = 0;
    size_t index = 0;
    while (index < length && count < 4) {
        long value = 0;
        int digits = 0;
        while (index < length && (text[index] == ' ' || text[index] == ',')) index++;
        while (index < length && text[index] >= '0' && text[index] <= '9' && digits < 7) {
            value = value * 10 + (text[index] - '0');
            digits++;
            index++;
        }
        if (!digits) return 0;
        /* a fractional part does not change the aspect enough to matter */
        if (index < length && text[index] == '.') {
            index++;
            while (index < length && text[index] >= '0' && text[index] <= '9') index++;
        }
        values[count++] = value;
    }
    if (count != 4 || values[2] <= 0 || values[3] <= 0) return 0;
    *width = values[2];
    *height = values[3];
    return 1;
}

static long pk_story_attr_number(const pk_html *doc, pk_span tag, const char *name) {
    pk_span raw;
    long value = 0;
    if (pk_html_attr(doc, tag, name, &raw) != PK_OK || !raw.length) return 0;
    if (pk_number_compact(doc->data + raw.offset, raw.length, &value) != PK_OK || value < 0) return 0;
    return value;
}

pk_status pk_story_content(const pk_html *doc, pk_span *content) {
    pk_span tag;
    pk_status status;
    if (content) *content = PK_SPAN_NONE;
    if (!doc || !doc->data || !content) return PK_ERR_INVALID;
    if (pk_html_find(doc, 0, "div", "story__content-inner", &tag) != PK_OK) return PK_ERR_NOT_FOUND;
    status = pk_html_body(doc, tag, content);
    /* a cut-off post still has a readable beginning */
    return status == PK_ERR_INVALID ? PK_ERR_INVALID : PK_OK;
}

static int pk_story_add_text(const pk_html *doc, pk_span range,
                             pk_story_block *blocks, size_t capacity, size_t *count) {
    char probe[8];
    size_t written = 0;
    if (*count >= capacity || !range.length) return 1;
    /* a run that renders to nothing is markup between blocks */
    if (pk_text_plain(doc->data + range.offset, range.length, probe, sizeof(probe), &written) == PK_ERR_TOO_LARGE) return 1;
    if (!written) return 1;
    blocks[*count].type = PK_BLOCK_TEXT;
    blocks[*count].text = range;
    blocks[*count].url = PK_SPAN_NONE;
    blocks[*count].poster = PK_SPAN_NONE;
    blocks[*count].duration = PK_SPAN_NONE;
    blocks[*count].width = 0;
    blocks[*count].height = 0;
    (*count)++;
    return *count < capacity;
}

size_t pk_story_blocks(const pk_html *doc, pk_span content, pk_story_block *blocks, size_t capacity) {
    size_t count = 0;
    size_t cursor;
    size_t limit;
    size_t visited = 0;
    if (!doc || !doc->data || !blocks || !capacity) return 0;
    if (capacity > PK_STORY_MAX_BLOCKS) capacity = PK_STORY_MAX_BLOCKS;
    if (content.offset > doc->length || content.length > doc->length - content.offset) return 0;
    cursor = content.offset;
    limit = content.offset + content.length;

    while (count < capacity && cursor < limit && visited++ < PK_STORY_MAX_BLOCKS * 4) {
        pk_span range;
        pk_span image;
        pk_span video;
        pk_span media;
        pk_block_type type;
        pk_span text_before;
        range.offset = cursor;
        range.length = limit - cursor;

        {
            int has_image = pk_html_find_in(doc, range, "img", NULL, &image) == PK_OK;
            int has_video = pk_html_find_in(doc, range, "video", NULL, &video) == PK_OK;
            if (!has_image && !has_video) break;
            if (has_image && (!has_video || image.offset < video.offset)) {
                media = image;
                type = PK_BLOCK_IMAGE;
            } else {
                media = video;
                type = PK_BLOCK_VIDEO;
            }
        }

        text_before.offset = cursor;
        text_before.length = media.offset - cursor;
        if (!pk_story_add_text(doc, text_before, blocks, capacity, &count)) return count;

        blocks[count].type = type;
        blocks[count].text = PK_SPAN_NONE;
        blocks[count].url = PK_SPAN_NONE;
        blocks[count].poster = PK_SPAN_NONE;
        blocks[count].duration = PK_SPAN_NONE;
        blocks[count].width = 0;
        blocks[count].height = 0;
        if (type == PK_BLOCK_IMAGE) {
            pk_span stretch;
            pk_span view_box;
            if (pk_html_find_in(doc, text_before, "svg", "story-image__stretch", &stretch) == PK_OK &&
                pk_html_attr(doc, stretch, "viewBox", &view_box) == PK_OK)
                pk_story_view_box(doc->data + view_box.offset, view_box.length, &blocks[count].width, &blocks[count].height);
            pk_html_attr_any(doc, media, pk_story_image_attributes,
                             PK_COUNT_OF(pk_story_image_attributes), &blocks[count].url);
            cursor = media.offset + media.length;
        } else {
            pk_span body;
            pk_span source;
            int source_found = 0;
            /* modern markup keeps the playable extension on the source child, data-source may be only a
               stream base name */
            if (pk_html_body(doc, media, &body) == PK_OK && body.length &&
                pk_html_find_in(doc, body, "source", NULL, &source) == PK_OK &&
                pk_html_attr_any(doc, source, pk_story_video_attributes,
                                 PK_COUNT_OF(pk_story_video_attributes), &blocks[count].url) == PK_OK)
                source_found = 1;
            if (!source_found)
                pk_html_attr_any(doc, media, pk_story_video_attributes,
                                 PK_COUNT_OF(pk_story_video_attributes), &blocks[count].url);
            pk_html_attr_any(doc, media, pk_story_poster_attributes,
                             PK_COUNT_OF(pk_story_poster_attributes), &blocks[count].poster);
            pk_html_attr(doc, media, "data-duration", &blocks[count].duration);
            blocks[count].width = pk_story_attr_number(doc, media, "data-width");
            blocks[count].height = pk_story_attr_number(doc, media, "data-height");
            if (!blocks[count].width || !blocks[count].height) blocks[count].width = blocks[count].height = 0;
            if (pk_html_body(doc, media, &body) == PK_OK)
                cursor = body.offset + body.length;
            else
                cursor = media.offset + media.length;
        }
        if (blocks[count].url.length) count++;
    }

    if (count < capacity && cursor < limit) {
        pk_span tail;
        tail.offset = cursor;
        tail.length = limit - cursor;
        pk_story_add_text(doc, tail, blocks, capacity, &count);
    }
    return count;
}

size_t pk_story_links(const pk_html *doc, pk_span range, pk_span *hrefs, size_t capacity) {
    size_t count = 0;
    size_t cursor;
    size_t limit;
    size_t visited = 0;
    if (!doc || !doc->data || !hrefs || !capacity) return 0;
    if (capacity > PK_STORY_MAX_LINKS) capacity = PK_STORY_MAX_LINKS;
    if (range.offset > doc->length || range.length > doc->length - range.offset) return 0;
    cursor = range.offset;
    limit = range.offset + range.length;

    while (count < capacity && cursor < limit && visited++ < PK_STORY_MAX_LINKS * 8) {
        pk_span search;
        pk_span anchor;
        pk_span href;
        search.offset = cursor;
        search.length = limit - cursor;
        if (pk_html_find_in(doc, search, "a", NULL, &anchor) != PK_OK) break;
        cursor = anchor.offset + anchor.length;
        /* an anchor without href is a named target */
        if (pk_html_attr(doc, anchor, "href", &href) != PK_OK || !href.length) continue;
        hrefs[count++] = href;
    }
    return count;
}

pk_status pk_story_csrf(const pk_html *doc, pk_span *token) {
    size_t index;
    const char needle[] = "\"csrfToken\":";
    size_t needle_length = sizeof(needle) - 1;
    if (token) *token = PK_SPAN_NONE;
    if (!doc || !doc->data || !token) return PK_ERR_INVALID;
    /* the token sits in a json field of an inline script, so it is found as bytes */
    if (doc->length < needle_length) return PK_ERR_NOT_FOUND;
    for (index = 0; index + needle_length < doc->length; index++) {
        size_t scan;
        if (memcmp(doc->data + index, needle, needle_length)) continue;
        scan = index + needle_length;
        while (scan < doc->length && (doc->data[scan] == ' ' || doc->data[scan] == '\t')) scan++;
        if (scan >= doc->length || doc->data[scan] != '"') continue;
        scan++;
        token->offset = scan;
        while (scan < doc->length && doc->data[scan] != '"' && doc->data[scan] != '\n') scan++;
        if (scan >= doc->length || doc->data[scan] != '"' || scan == token->offset) {
            *token = PK_SPAN_NONE;
            continue;
        }
        token->length = scan - token->offset;
        return PK_OK;
    }
    return PK_ERR_NOT_FOUND;
}

pk_status pk_story_score(const pk_html *doc, long *score) {
    pk_span article, body, value, block, count;
    char text[64];
    size_t written = 0;
    if (score) *score = 0;
    if (!doc || !doc->data || !score) return PK_ERR_INVALID;
    if (pk_html_find(doc, 0, "article", "story", &article) != PK_OK) return PK_ERR_NOT_FOUND;
    if (pk_html_attr(doc, article, "data-rating", &value) == PK_OK &&
        pk_number_compact(doc->data + value.offset, value.length, score) == PK_OK) return PK_OK;
    if (pk_html_body(doc, article, &body) == PK_ERR_INVALID) return PK_ERR_INVALID;
    if (pk_html_find_in(doc, body, "div", "story__rating-block", &block) != PK_OK) return PK_ERR_NOT_FOUND;
    if (pk_html_body(doc, block, &body) == PK_ERR_INVALID) return PK_ERR_INVALID;
    if (pk_html_find_in(doc, body, "div", "story__rating-count", &count) == PK_OK &&
        pk_html_body(doc, count, &value) == PK_OK &&
        pk_text_plain(doc->data + value.offset, value.length, text, sizeof(text), &written) == PK_OK &&
        pk_number_compact(text, written, score) == PK_OK) return PK_OK;
    if (pk_html_attr(doc, block, "aria-label", &value) == PK_OK &&
        pk_rating_label(doc->data + value.offset, value.length, score)) return PK_OK;
    return PK_ERR_NOT_FOUND;
}

size_t pk_reactions_parse(const pk_html *doc, pk_span range, pk_reaction *reactions, size_t capacity) {
    size_t count = 0;
    size_t cursor;
    size_t limit;
    size_t visited = 0;
    if (!doc || !doc->data || !reactions || !capacity) return 0;
    if (capacity > PK_REACTIONS_MAX) capacity = PK_REACTIONS_MAX;
    if (range.offset > doc->length || range.length > doc->length - range.offset) return 0;
    cursor = range.offset;
    limit = range.offset + range.length;

    while (count < capacity && cursor < limit && visited++ < PK_REACTIONS_MAX * 4) {
        pk_span button;
        pk_span value;
        pk_span search;
        long identifier = 0;
        long amount = 0;
        search.offset = cursor;
        search.length = limit - cursor;
        if (pk_html_find_in(doc, search, "button", "emotion-btn", &button) != PK_OK) break;
        cursor = button.offset + button.length;
        if (pk_html_attr(doc, button, "data-id", &value) != PK_OK ||
            pk_number_compact(doc->data + value.offset, value.length, &identifier) != PK_OK ||
            identifier <= 0) continue;
        if (pk_html_attr(doc, button, "data-count", &value) != PK_OK ||
            pk_number_compact(doc->data + value.offset, value.length, &amount) != PK_OK ||
            amount < 0) continue;
        reactions[count].id = identifier;
        reactions[count].count = amount;
        reactions[count].active = pk_html_has_class(doc, button, "emotion-btn_active");
        count++;
    }
    return count;
}

pk_status pk_story_reactions(const pk_html *doc, pk_reaction *reactions, size_t capacity, size_t *count) {
    pk_span tag;
    pk_span body;
    if (count) *count = 0;
    if (!doc || !doc->data || !reactions || !capacity || !count) return PK_ERR_INVALID;
    /* every comment has a bar too, only the post's own counts */
    if (pk_html_find(doc, 0, "div", "story__emotions", &tag) != PK_OK) return PK_ERR_NOT_FOUND;
    if (pk_html_body(doc, tag, &body) == PK_ERR_INVALID) return PK_ERR_INVALID;
    *count = pk_reactions_parse(doc, body, reactions, capacity);
    return PK_OK;
}
