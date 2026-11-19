#include "pk_html.h"

#include <string.h>

#include "pk_text.h"

static int pk_html_lower(int c) {
    return (c >= 'A' && c <= 'Z') ? c + 32 : c;
}

static int pk_html_space(char c) {
    return c == ' ' || c == '\t' || c == '\r' || c == '\n' || c == '\f' || c == '\v';
}

static int pk_html_equals_ci(const char *a, size_t a_length, const char *b, size_t b_length) {
    size_t index;
    if (a_length != b_length) return 0;
    for (index = 0; index < a_length; index++)
        if (pk_html_lower((unsigned char)a[index]) != pk_html_lower((unsigned char)b[index])) return 0;
    return 1;
}

/* '<' inside javascript or css is just a byte, a walk that enters would count a "</div>" in a string */
static int pk_html_opaque(const char *name, size_t length) {
    return pk_html_equals_ci(name, length, "script", 6) ||
           pk_html_equals_ci(name, length, "style", 5) ||
           pk_html_equals_ci(name, length, "noscript", 8) ||
           pk_html_equals_ci(name, length, "template", 8);
}

pk_status pk_html_init(pk_html *doc, const char *data, size_t length) {
    if (!doc) return PK_ERR_INVALID;
    doc->data = NULL;
    doc->length = 0;
    if (!data) return PK_ERR_INVALID;
    if (length > PK_MAX_DOCUMENT_BYTES) return PK_ERR_TOO_LARGE;
    doc->data = data;
    doc->length = length;
    return PK_OK;
}

/* an unterminated tag reports the end of the document */
static size_t pk_html_tag_end(const pk_html *doc, size_t start) {
    size_t index = start + 1;
    char quote = 0;
    while (index < doc->length) {
        char c = doc->data[index];
        if (quote) {
            if (c == quote) quote = 0;
        } else if (c == '"' || c == '\'') {
            quote = c;
        } else if (c == '>') {
            return index + 1;
        }
        index++;
    }
    return doc->length;
}

static void pk_html_tag_name(const pk_html *doc, size_t start, pk_span *name, int *closing) {
    size_t index = start + 1;
    size_t begin;
    *closing = 0;
    if (index < doc->length && doc->data[index] == '/') {
        *closing = 1;
        index++;
    }
    begin = index;
    while (index < doc->length && !pk_html_space(doc->data[index]) &&
           doc->data[index] != '>' && doc->data[index] != '/') index++;
    name->offset = begin;
    name->length = index - begin;
}

/* the html rule for these elements: the first literal "</name" */
static size_t pk_html_skip_opaque(const pk_html *doc, size_t from, pk_span name) {
    size_t scan = from;
    const char *label = doc->data + name.offset;
    while (scan + name.length + 2 < doc->length) {
        if (doc->data[scan] == '<' && doc->data[scan + 1] == '/' &&
            pk_html_equals_ci(doc->data + scan + 2, name.length, label, name.length)) {
            char after = doc->data[scan + 2 + name.length];
            if (after == '>' || pk_html_space(after)) return pk_html_tag_end(doc, scan);
        }
        scan++;
    }
    return doc->length;
}

pk_status pk_html_attr(const pk_html *doc, pk_span tag, const char *name, pk_span *value) {
    size_t index;
    size_t end;
    size_t name_length;
    if (value) *value = PK_SPAN_NONE;
    if (!doc || !doc->data || !name || !value) return PK_ERR_INVALID;
    if (tag.offset > doc->length || tag.length > doc->length - tag.offset || tag.length < 2) return PK_ERR_INVALID;
    name_length = strlen(name);
    if (!name_length) return PK_ERR_INVALID;

    /* start past the name so an attribute cannot match it, stop before '>' so the search stays in the tag */
    index = tag.offset + 1;
    end = tag.offset + tag.length - 1;
    while (index < end && !pk_html_space(doc->data[index])) index++;

    while (index < end) {
        size_t key_start;
        size_t key_end;
        while (index < end && (pk_html_space(doc->data[index]) || doc->data[index] == '/')) index++;
        if (index >= end) break;
        key_start = index;
        while (index < end && !pk_html_space(doc->data[index]) && doc->data[index] != '=' && doc->data[index] != '/') index++;
        key_end = index;
        while (index < end && pk_html_space(doc->data[index])) index++;
        if (index >= end || doc->data[index] != '=') {
            if (pk_html_equals_ci(doc->data + key_start, key_end - key_start, name, name_length)) return PK_ERR_NOT_FOUND;
            continue;
        }
        index++;
        while (index < end && pk_html_space(doc->data[index])) index++;
        {
            size_t value_start;
            size_t value_end;
            if (index < end && (doc->data[index] == '"' || doc->data[index] == '\'')) {
                char quote = doc->data[index++];
                value_start = index;
                while (index < end && doc->data[index] != quote) index++;
                value_end = index;
                if (index < end) index++;
            } else {
                value_start = index;
                while (index < end && !pk_html_space(doc->data[index])) index++;
                value_end = index;
            }
            if (pk_html_equals_ci(doc->data + key_start, key_end - key_start, name, name_length)) {
                value->offset = value_start;
                value->length = value_end - value_start;
                return PK_OK;
            }
        }
    }
    return PK_ERR_NOT_FOUND;
}

pk_status pk_html_attr_any(const pk_html *doc, pk_span tag, const char *const *names, size_t count, pk_span *value) {
    size_t index;
    if (value) *value = PK_SPAN_NONE;
    if (!names || !count) return PK_ERR_INVALID;
    for (index = 0; index < count; index++) {
        pk_span found;
        if (pk_html_attr(doc, tag, names[index], &found) == PK_OK && found.length) {
            *value = found;
            return PK_OK;
        }
    }
    return PK_ERR_NOT_FOUND;
}

int pk_html_has_class(const pk_html *doc, pk_span tag, const char *token) {
    pk_span classes;
    size_t token_length;
    size_t index = 0;
    if (!token) return 1;
    token_length = strlen(token);
    if (!token_length) return 1;
    if (pk_html_attr(doc, tag, "class", &classes) != PK_OK) return 0;
    /* "story__title" must not match inside "story__title-link" */
    while (index < classes.length) {
        size_t start;
        while (index < classes.length && pk_html_space(doc->data[classes.offset + index])) index++;
        start = index;
        while (index < classes.length && !pk_html_space(doc->data[classes.offset + index])) index++;
        if (index > start && pk_html_equals_ci(doc->data + classes.offset + start, index - start, token, token_length))
            return 1;
    }
    return 0;
}

pk_status pk_html_find_in(const pk_html *doc, pk_span range, const char *name, const char *cls, pk_span *tag) {
    size_t index;
    size_t limit;
    size_t name_length;
    size_t visited = 0;
    if (tag) *tag = PK_SPAN_NONE;
    if (!doc || !doc->data || !name || !tag) return PK_ERR_INVALID;
    name_length = strlen(name);
    if (!name_length) return PK_ERR_INVALID;
    if (range.offset > doc->length || range.length > doc->length - range.offset) return PK_ERR_INVALID;
    index = range.offset;
    limit = range.offset + range.length;

    while (index < limit) {
        pk_span found;
        pk_span element;
        int closing;
        size_t end;
        if (doc->data[index] != '<') { index++; continue; }
        if (++visited > PK_HTML_MAX_TAGS) return PK_ERR_TOO_LARGE;
        pk_html_tag_name(doc, index, &element, &closing);
        end = pk_html_tag_end(doc, index);
        if (end > limit) return PK_ERR_NOT_FOUND;
        if (end <= index) return PK_ERR_INVALID;
        /* the name is compared before the body is skipped, so a search for "script" still finds the embedded json */
        if (closing || !pk_html_equals_ci(doc->data + element.offset, element.length, name, name_length)) {
            if (!closing && pk_html_opaque(doc->data + element.offset, element.length))
                index = pk_html_skip_opaque(doc, end, element);
            else
                index = end;
            continue;
        }
        found.offset = index;
        found.length = end - index;
        if (cls && !pk_html_has_class(doc, found, cls)) {
            index = end;
            continue;
        }
        *tag = found;
        return PK_OK;
    }
    return PK_ERR_NOT_FOUND;
}

pk_status pk_html_find(const pk_html *doc, size_t from, const char *name, const char *cls, pk_span *tag) {
    pk_span range;
    if (tag) *tag = PK_SPAN_NONE;
    if (!doc || !doc->data || from > doc->length) return PK_ERR_INVALID;
    range.offset = from;
    range.length = doc->length - from;
    return pk_html_find_in(doc, range, name, cls, tag);
}

pk_status pk_html_body(const pk_html *doc, pk_span tag, pk_span *body) {
    pk_span name;
    int closing;
    size_t index;
    size_t depth = 1;
    size_t visited = 0;
    if (body) *body = PK_SPAN_NONE;
    if (!doc || !doc->data || !body) return PK_ERR_INVALID;
    if (tag.offset >= doc->length || tag.length < 2 || tag.length > doc->length - tag.offset) return PK_ERR_INVALID;

    pk_html_tag_name(doc, tag.offset, &name, &closing);
    if (closing || !name.length) return PK_ERR_INVALID;
    index = tag.offset + tag.length;
    if (tag.length >= 2 && doc->data[tag.offset + tag.length - 2] == '/') {
        body->offset = index;
        body->length = 0;
        return PK_OK;
    }
    if (pk_html_opaque(doc->data + name.offset, name.length)) {
        size_t opaque_end = pk_html_skip_opaque(doc, index, name);
        body->offset = index;
        body->length = opaque_end > index ? opaque_end - index : 0;
        return PK_OK;
    }

    while (index < doc->length) {
        pk_span element;
        int element_closing;
        size_t end;
        if (doc->data[index] != '<') { index++; continue; }
        if (++visited > PK_HTML_MAX_TAGS) return PK_ERR_TOO_LARGE;
        pk_html_tag_name(doc, index, &element, &element_closing);
        end = pk_html_tag_end(doc, index);
        if (end <= index) return PK_ERR_INVALID;
        if (!element_closing && pk_html_opaque(doc->data + element.offset, element.length)) {
            index = pk_html_skip_opaque(doc, end, element);
            continue;
        }
        if (pk_html_equals_ci(doc->data + element.offset, element.length,
                              doc->data + name.offset, name.length)) {
            if (element_closing) {
                if (--depth == 0) {
                    body->offset = tag.offset + tag.length;
                    body->length = index - body->offset;
                    return PK_OK;
                }
            } else if (end < index + 2 || doc->data[end - 2] != '/') {
                if (++depth > PK_HTML_MAX_DEPTH) return PK_ERR_INVALID;
            }
        }
        index = end;
    }
    /* a truncated story still has a readable beginning */
    body->offset = tag.offset + tag.length;
    body->length = doc->length - body->offset;
    return PK_ERR_TRUNCATED;
}
