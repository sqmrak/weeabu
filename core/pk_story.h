#ifndef PK_STORY_H
#define PK_STORY_H

#include <stddef.h>

#include "pk_html.h"
#include "pk_span.h"
#include "pk_status.h"

/* caps what a hostile page can put into the table view */
#define PK_STORY_MAX_BLOCKS 96
#define PK_REACTIONS_MAX 32
#define PK_STORY_MAX_LINKS 8

typedef enum {
    PK_BLOCK_TEXT = 0,
    PK_BLOCK_IMAGE,
    PK_BLOCK_VIDEO
} pk_block_type;

typedef struct {
    pk_block_type type;
    pk_span text;     /* raw markup for a text block, for pk_text_plain */
    pk_span url;      /* raw attribute for media, for pk_url_normalize */
    pk_span poster;   /* the still a video shows before it is played */
    pk_span duration;
    long width;
    long height;
} pk_story_block;

/* "0 0 700 490", the svg the site puts before an image to reserve its box, only the last two numbers matter */
int pk_story_view_box(const char *text, size_t length, long *width, long *height);

typedef struct {
    long id;
    long count;
    int active;   /* the signed in reader already picked this one */
} pk_reaction;

pk_status pk_story_content(const pk_html *doc, pk_span *content);

size_t pk_story_blocks(const pk_html *doc, pk_span content, pk_story_block *blocks, size_t capacity);

/* raw attributes for pk_url_normalize_link, the caller decides which it can open */
size_t pk_story_links(const pk_html *doc, pk_span range, pk_span *hrefs, size_t capacity);

pk_status pk_story_score(const pk_html *doc, long *score);

pk_status pk_story_csrf(const pk_html *doc, pk_span *token);

size_t pk_reactions_parse(const pk_html *doc, pk_span range, pk_reaction *reactions, size_t capacity);

/* comments carry their own bars */
pk_status pk_story_reactions(const pk_html *doc, pk_reaction *reactions, size_t capacity, size_t *count);

#endif
