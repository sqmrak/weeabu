#ifndef PK_FEED_H
#define PK_FEED_H

#include <stddef.h>

#include "pk_html.h"
#include "pk_span.h"
#include "pk_status.h"
#include "pk_story.h"

/* caps what a hostile page can put into the caller's array */
#define PK_FEED_MAX_POSTS 50
#define PK_POST_MAX_TAGS 4
#define PK_POST_MAX_TEXT 24
#define PK_POST_MAX_MEDIA 24

typedef struct {
    pk_block_type type; /* PK_BLOCK_IMAGE or PK_BLOCK_VIDEO */
    pk_span url;
    pk_span poster;
    pk_span duration;
} pk_post_media;

/* spans point into the parsed document and live as long as it does */
typedef struct {
    pk_span url;
    pk_span title;
    pk_span author;
    pk_span story_id;
    pk_span date;
    pk_span image_url;
    pk_span avatar_url;
    pk_span community;
    pk_span excerpt;
    pk_span parent_url;
    pk_span parent_title;
    /* the page ships the part behind the cut inside the card */
    pk_span text_blocks[PK_POST_MAX_TEXT];
    size_t text_count;
    size_t text_visible_count;
    pk_post_media media[PK_POST_MAX_MEDIA];
    size_t media_count;
    long media_width;
    long media_height;
    int has_hidden;
    pk_span reactions;
    pk_span tags[PK_POST_MAX_TAGS];
    size_t tag_count;
    long score;
    int score_known;
    long comments;
    int has_video;
} pk_post;

/* a card without a link or a title is skipped, neither screen can use half of one */
size_t pk_feed_parse(const pk_html *doc, pk_post *posts, size_t capacity);

#endif
