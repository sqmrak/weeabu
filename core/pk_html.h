#ifndef PK_HTML_H
#define PK_HTML_H

#include <stddef.h>

#include "pk_span.h"
#include "pk_status.h"

/* a page with 200000 tags is an attack on a slow phone, not a pikabu page */
#define PK_HTML_MAX_TAGS 200000u
#define PK_HTML_MAX_DEPTH 64u

typedef struct {
    const char *data;
    size_t length;
} pk_html;

pk_status pk_html_init(pk_html *doc, const char *data, size_t length);

/* a caller iterates by searching again from tag.offset + tag.length */
pk_status pk_html_find(const pk_html *doc, size_t from, const char *name, const char *cls, pk_span *tag);

/* a card matches only its own markup, never the next card */
pk_status pk_html_find_in(const pk_html *doc, pk_span range, const char *name, const char *cls, pk_span *tag);

/* entities stay encoded: url values go through pk_url_normalize, text values through pk_text_plain */
pk_status pk_html_attr(const pk_html *doc, pk_span tag, const char *name, pk_span *value);

pk_status pk_html_attr_any(const pk_html *doc, pk_span tag, const char *const *names, size_t count, pk_span *value);

/* an element of the same name inside is counted */
pk_status pk_html_body(const pk_html *doc, pk_span tag, pk_span *body);

int pk_html_has_class(const pk_html *doc, pk_span tag, const char *token);

#endif
