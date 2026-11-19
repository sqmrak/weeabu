#include "pk_comments.h"

#include <string.h>

#include "pk_text.h"

static const char *const pk_comment_media_attributes[] = {
    "data-large-image", "data-src", "src"
};

#define PK_COUNT_OF(array) (sizeof(array) / sizeof((array)[0]))

/* data-meta packs parent and indent into one attribute ("pid=0;aid=...;de=0") */
static pk_status pk_meta_field(const pk_html *doc, pk_span meta, const char *key, pk_span *value) {
    size_t key_length = strlen(key);
    size_t index = 0;
    if (value) *value = PK_SPAN_NONE;
    if (!meta.length || !value) return PK_ERR_NOT_FOUND;
    while (index < meta.length) {
        size_t start = index;
        size_t split;
        while (index < meta.length && doc->data[meta.offset + index] != ';') index++;
        split = start;
        while (split < index && doc->data[meta.offset + split] != '=') split++;
        if (split - start == key_length &&
            !memcmp(doc->data + meta.offset + start, key, key_length) && split < index) {
            value->offset = meta.offset + split + 1;
            value->length = index - split - 1;
            return PK_OK;
        }
        index++;
    }
    return PK_ERR_NOT_FOUND;
}

static long pk_span_number(const pk_html *doc, pk_span span) {
    long value = 0;
    if (!span.length) return 0;
    if (pk_number_compact(doc->data + span.offset, span.length, &value) != PK_OK) return 0;
    return value;
}

static int pk_comment_score(const pk_html *doc, pk_span range, long *value, int *hidden) {
    pk_span tag, body, label;
    char text[64];
    size_t written = 0;
    *value = 0;
    *hidden = 0;
    if ((pk_html_find_in(doc, range, "span", "comment__rating-count", &tag) == PK_OK ||
         pk_html_find_in(doc, range, "div", "comment__rating-count", &tag) == PK_OK) &&
        pk_html_body(doc, tag, &body) == PK_OK && body.length &&
        pk_text_plain(doc->data + body.offset, body.length, text, sizeof(text), &written) == PK_OK &&
        pk_number_compact(text, written, value) == PK_OK) return 1;
    if (pk_html_find_in(doc, range, "div", "comment__rating", &tag) != PK_OK ||
        pk_html_attr(doc, tag, "aria-label", &label) != PK_OK) return 0;
    if (pk_text_decode_entities(doc->data + label.offset, label.length, text, sizeof(text), &written) == PK_OK &&
        !strcmp(text, "Низкий рейтинг")) *hidden = 1;
    return pk_rating_label(doc->data + label.offset, label.length, value);
}

static void pk_comment_media(const pk_html *doc, pk_span body, pk_comment *comment) {
    pk_span tag;
    size_t from = body.offset;
    size_t limit = body.offset + body.length;
    size_t visited = 0;
    while (from < limit && visited++ < 32) {
        pk_span range;
        pk_span marker;
        range.offset = from;
        range.length = limit - from;
        if (pk_html_find_in(doc, range, "img", NULL, &tag) != PK_OK) return;
        from = tag.offset + tag.length;
        /* the header avatar is an <img> too, only media the viewer opens counts */
        if (!pk_html_has_class(doc, tag, "comment__sticker") &&
            pk_html_attr(doc, tag, "data-viewable", &marker) != PK_OK &&
            pk_html_attr(doc, tag, "data-large-image", &marker) != PK_OK) continue;
        if (pk_html_attr_any(doc, tag, pk_comment_media_attributes,
                             PK_COUNT_OF(pk_comment_media_attributes), &comment->media_url) != PK_OK) continue;
        comment->media_is_sticker = pk_html_has_class(doc, tag, "comment__sticker") ||
                                    pk_html_has_class(doc, tag, "sticker");
        return;
    }
}

size_t pk_comments_parse(const pk_html *doc, pk_comment *comments, size_t capacity) {
    size_t count = 0;
    size_t from = 0;
    size_t visited = 0;
    if (!doc || !doc->data || !comments || !capacity) return 0;
    if (capacity > PK_COMMENTS_MAX) capacity = PK_COMMENTS_MAX;

    while (count < capacity && from < doc->length && visited++ < PK_COMMENTS_MAX * 2) {
        pk_comment *comment = &comments[count];
        pk_span tag;
        pk_span body;
        pk_span content;
        pk_span meta;
        pk_span inner;
        if (pk_html_find(doc, from, "div", "comment", &tag) != PK_OK) break;
        /* replies nest inside their parent, so the walk goes past the opening tag only */
        from = tag.offset + tag.length;
        if (pk_html_body(doc, tag, &body) == PK_ERR_INVALID) continue;
        if (!body.length) continue;

        if (pk_html_find_in(doc, body, "div", "comment__content", &content) != PK_OK) continue;
        if (pk_html_body(doc, content, &inner) == PK_ERR_INVALID) continue;

        memset(comment, 0, sizeof(*comment));
        comment->body = inner;
        pk_html_attr(doc, tag, "data-id", &comment->comment_id);

        if (pk_html_attr(doc, tag, "data-meta", &meta) == PK_OK) {
            pk_span field;
            if (pk_meta_field(doc, meta, "pid", &field) == PK_OK) comment->parent_id = field;
            if (pk_meta_field(doc, meta, "de", &field) == PK_OK) comment->indent = pk_span_number(doc, field);
        }
        if (!comment->indent) {
            pk_span indent;
            if (pk_html_attr(doc, tag, "data-indent", &indent) == PK_OK) comment->indent = pk_span_number(doc, indent);
        }

        {
            /* the like icon in the header and data-author-avatar belong to other users, only the name link
               img is the commenter */
            pk_span link;
            pk_span link_body;
            pk_span image;
            static const char *const attributes[] = { "data-src", "src" };
            if (pk_html_find_in(doc, body, "a", "comment__user", &link) == PK_OK &&
                pk_html_body(doc, link, &link_body) == PK_OK && link_body.length &&
                pk_html_find_in(doc, link_body, "img", NULL, &image) == PK_OK)
                pk_html_attr_any(doc, image, attributes, PK_COUNT_OF(attributes), &comment->avatar_url);
        }
        {
            pk_span author;
            if (pk_html_find_in(doc, body, "a", "comment__user", &author) == PK_OK &&
                pk_html_attr(doc, author, "data-name", &comment->author) != PK_OK) {
                pk_span nick;
                if (pk_html_find_in(doc, body, "span", "user__nick", &nick) == PK_OK)
                    pk_html_body(doc, nick, &comment->author);
            }
        }
        {
            pk_span date;
            if (pk_html_find_in(doc, body, "time", "comment__datetime", &date) == PK_OK &&
                (pk_html_body(doc, date, &comment->date) != PK_OK || !comment->date.length))
                pk_html_attr(doc, date, "datetime", &comment->date);
        }

        {
            pk_span own, own_body;
            if (pk_html_find_in(doc, body, "div", "comment__body", &own) == PK_OK &&
                pk_html_body(doc, own, &own_body) == PK_OK)
                comment->score_known = pk_comment_score(doc, own_body, &comment->score, &comment->score_hidden);
            else
                comment->score_known = pk_comment_score(doc, body, &comment->score, &comment->score_hidden);
        }
        pk_comment_media(doc, inner, comment);
        {
            /* replies live in a sibling container after comment__body */
            pk_span own;
            pk_span emotions;
            pk_span emotions_body;
            if (pk_html_find_in(doc, body, "div", "comment__body", &own) == PK_OK &&
                pk_html_body(doc, own, &own) != PK_ERR_INVALID &&
                pk_html_find_in(doc, own, "div", "comment__emotions", &emotions) == PK_OK &&
                pk_html_body(doc, emotions, &emotions_body) != PK_ERR_INVALID)
                comment->reactions = emotions_body;
        }
        count++;
    }
    return count;
}

/* one endpoint with a fixed shape: `{"min":N,"tree":[[offset,flags,[children]],...]}`, so a small scanner
   beats a json parser */
typedef struct {
    const char *data;
    size_t length;
    size_t index;
    long minimum;
    long *ids;
    size_t capacity;
    size_t count;
    int failed;
} pk_tree_scan;

static void pk_tree_spaces(pk_tree_scan *scan) {
    while (scan->index < scan->length) {
        char c = scan->data[scan->index];
        if (c != ' ' && c != '\t' && c != '\r' && c != '\n') break;
        scan->index++;
    }
}

static int pk_tree_byte(pk_tree_scan *scan, char expected) {
    pk_tree_spaces(scan);
    if (scan->index >= scan->length || scan->data[scan->index] != expected) return 0;
    scan->index++;
    return 1;
}

static int pk_tree_number(pk_tree_scan *scan, long *value) {
    long result = 0;
    int negative = 0;
    size_t digits = 0;
    pk_tree_spaces(scan);
    if (scan->index < scan->length && scan->data[scan->index] == '-') {
        negative = 1;
        scan->index++;
    }
    while (scan->index < scan->length) {
        char c = scan->data[scan->index];
        if (c < '0' || c > '9') break;
        if (result > (2000000000L - (c - '0')) / 10) return 0;
        result = result * 10 + (c - '0');
        scan->index++;
        digits++;
    }
    if (!digits) return 0;
    *value = negative ? -result : result;
    return 1;
}

static int pk_tree_key(pk_tree_scan *scan, const char *name) {
    size_t name_length = strlen(name);
    pk_tree_spaces(scan);
    if (scan->length - scan->index < name_length + 3) return 0;
    if (scan->data[scan->index] != '"') return 0;
    if (memcmp(scan->data + scan->index + 1, name, name_length)) return 0;
    if (scan->data[scan->index + 1 + name_length] != '"') return 0;
    scan->index += name_length + 2;
    return pk_tree_byte(scan, ':');
}

static void pk_tree_nodes(pk_tree_scan *scan, size_t depth);

static void pk_tree_node(pk_tree_scan *scan, size_t depth) {
    long offset = 0;
    long flags = 0;
    if (!pk_tree_byte(scan, '[')) { scan->failed = 1; return; }
    if (!pk_tree_number(scan, &offset)) { scan->failed = 1; return; }
    if (!pk_tree_byte(scan, ',')) { scan->failed = 1; return; }
    if (!pk_tree_number(scan, &flags)) { scan->failed = 1; return; }
    {
        long identifier = scan->minimum + offset;
        /* pikabu never issues an id at or below zero */
        if (identifier > 0 && scan->count < scan->capacity) scan->ids[scan->count++] = identifier;
    }
    if (pk_tree_byte(scan, ',')) {
        pk_tree_nodes(scan, depth + 1);
        if (scan->failed) return;
    }
    if (!pk_tree_byte(scan, ']')) scan->failed = 1;
}

static void pk_tree_nodes(pk_tree_scan *scan, size_t depth) {
    if (depth > PK_COMMENTS_MAX_DEPTH) { scan->failed = 1; return; }
    if (!pk_tree_byte(scan, '[')) { scan->failed = 1; return; }
    pk_tree_spaces(scan);
    if (pk_tree_byte(scan, ']')) return;
    for (;;) {
        pk_tree_node(scan, depth);
        if (scan->failed) return;
        if (pk_tree_byte(scan, ',')) continue;
        if (!pk_tree_byte(scan, ']')) scan->failed = 1;
        return;
    }
}

size_t pk_comments_tree_ids(const pk_html *doc, long *ids, size_t capacity) {
    pk_tree_scan scan;
    pk_span tag;
    pk_span body;
    size_t from = 0;
    size_t visited = 0;
    if (!doc || !doc->data || !ids || !capacity) return 0;
    if (capacity > PK_COMMENTS_MAX) capacity = PK_COMMENTS_MAX;

    for (;;) {
        pk_span entry;
        if (visited++ > PK_COMMENTS_MAX) return 0;
        if (pk_html_find(doc, from, "script", NULL, &tag) != PK_OK) return 0;
        from = tag.offset + tag.length;
        if (pk_html_attr(doc, tag, "data-entry", &entry) == PK_OK &&
            entry.length == 13 && !memcmp(doc->data + entry.offset, "comments-tree", 13)) break;
    }
    if (pk_html_body(doc, tag, &body) != PK_OK || !body.length) return 0;

    memset(&scan, 0, sizeof(scan));
    scan.data = doc->data + body.offset;
    scan.length = body.length;
    scan.ids = ids;
    scan.capacity = capacity;

    if (!pk_tree_byte(&scan, '{')) return 0;
    if (!pk_tree_key(&scan, "min") || !pk_tree_number(&scan, &scan.minimum)) return 0;
    if (!pk_tree_byte(&scan, ',')) return 0;
    if (!pk_tree_key(&scan, "tree")) return 0;
    pk_tree_nodes(&scan, 0);
    /* a tree that does not parse whole has ids that cannot be trusted */
    if (scan.failed) return 0;
    if (!pk_tree_byte(&scan, '}')) return 0;
    return scan.count;
}
