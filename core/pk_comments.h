#ifndef PK_COMMENTS_H
#define PK_COMMENTS_H

#include <stddef.h>

#include "pk_html.h"
#include "pk_span.h"
#include "pk_status.h"

/* the ajax endpoint is asked in batches, so this also caps the request size */
#define PK_COMMENTS_MAX 400
/* the tree json nests one level per reply */
#define PK_COMMENTS_MAX_DEPTH 64

typedef struct {
    pk_span comment_id;
    pk_span parent_id;
    pk_span author;
    pk_span avatar_url;
    pk_span body;
    pk_span date;
    pk_span media_url;
    /* a reply nests inside its parent, so the parent's element also holds the reply's bar: only this range
       is the comment's own */
    pk_span reactions;
    long score;
    int score_known;
    int score_hidden;
    long indent;
    int media_is_sticker;
} pk_comment;

/* a comment without a body is the deleted or hidden placeholder pikabu leaves in the tree */
size_t pk_comments_parse(const pk_html *doc, pk_comment *comments, size_t capacity);

/* ids are stored as offsets from a shared minimum, this is the only place that makes them absolute */
size_t pk_comments_tree_ids(const pk_html *doc, long *ids, size_t capacity);

#endif
