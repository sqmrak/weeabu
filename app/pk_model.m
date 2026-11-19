#import "pk_model.h"

#import "pk_lang.h"

#include "pk_comments.h"
#include "pk_feed.h"
#include "pk_html.h"
#include "pk_story.h"
#include "pk_text.h"
#include "pk_url.h"

static NSString *PKParentTitle(NSString *label);

@implementation PKPost
@synthesize title = _title, url = _url, author = _author, storyID = _storyID, summary = _summary;
@synthesize excerpt = _excerpt, fullText = _fullText, media = _media, parentURL = _parentURL, parentTitle = _parentTitle;
@synthesize imageURL = _imageURL, avatarURL = _avatarURL, community = _community, date = _date, tags = _tags;
@synthesize score = _score, comments = _comments;
@synthesize hasVideo = _hasVideo;
@synthesize reactions = _reactions;
@synthesize scoreKnown = _scoreKnown;
@synthesize imageWidth = _imageWidth, imageHeight = _imageHeight;
- (void)dealloc {
    [_title release]; [_url release]; [_author release]; [_storyID release]; [_summary release]; [_excerpt release]; [_fullText release]; [_media release]; [_parentURL release]; [_parentTitle release];
    [_imageURL release]; [_avatarURL release]; [_community release]; [_date release]; [_tags release]; [_reactions release];
    [super dealloc];
}
@end

@implementation PKComment
@synthesize commentID = _commentID, parentID = _parentID, author = _author, body = _body, date = _date;
@synthesize mediaURL = _mediaURL, score = _score, indent = _indent, mediaIsSticker = _mediaIsSticker;
@synthesize reactions = _reactions, links = _links, avatarURL = _avatarURL;
@synthesize scoreKnown = _scoreKnown, scoreHidden = _scoreHidden;
@synthesize mediaWidth = _mediaWidth, mediaHeight = _mediaHeight;
- (void)dealloc {
    [_commentID release]; [_parentID release]; [_author release]; [_body release]; [_date release];
    [_mediaURL release]; [_reactions release]; [_links release]; [_avatarURL release];
    [super dealloc];
}
@end

/* the core reports byte offsets and never copies, so the buffer must outlive every span */
@interface PKDocument : NSObject {
    NSData *_bytes;
    pk_html _doc;
}
+ (PKDocument *)documentWithHTML:(NSString *)html;
- (const pk_html *)handle;
- (NSString *)rawFromSpan:(pk_span)span;
- (NSString *)textFromSpan:(pk_span)span;
- (NSString *)urlFromSpan:(pk_span)span;
- (NSArray *)linksFromSpan:(pk_span)span;
@end

@implementation PKDocument

+ (PKDocument *)documentWithHTML:(NSString *)html {
    PKDocument *document;
    if (!html.length) return nil;
    document = [[[PKDocument alloc] init] autorelease];
    document->_bytes = [[html dataUsingEncoding:NSUTF8StringEncoding] retain];
    if (pk_html_init(&document->_doc, document->_bytes.bytes, document->_bytes.length) != PK_OK) return nil;
    return document;
}

- (const pk_html *)handle { return &_doc; }

- (NSString *)rawFromSpan:(pk_span)span {
    if (!span.length) return nil;
    return [[[NSString alloc] initWithBytes:(const char *)_bytes.bytes + span.offset
                                     length:span.length
                                   encoding:NSUTF8StringEncoding] autorelease];
}

- (NSString *)textFromSpan:(pk_span)span {
    NSMutableData *scratch;
    size_t written = 0;
    pk_status status;
    if (!span.length) return nil;
/* stripping markup and decoding entities only shortens the bytes, so the span length is room enough */
    scratch = [NSMutableData dataWithLength:span.length + 1];
    status = pk_text_plain((const char *)_bytes.bytes + span.offset, span.length,
                           scratch.mutableBytes, scratch.length, &written);
    if (status == PK_ERR_TOO_LARGE || !written) return nil;
    if (written > span.length) written = span.length;
    return [[[NSString alloc] initWithBytes:scratch.mutableBytes
                                     length:written
                                   encoding:NSUTF8StringEncoding] autorelease];
}

- (NSString *)urlFromSpan:(pk_span)span {
    char url[PK_MAX_URL_BYTES];
    size_t written = 0;
    if (!span.length) return nil;
/* a url the core refuses must never reach the network layer, so nil and not the raw attribute */
    if (pk_url_normalize((const char *)_bytes.bytes + span.offset, span.length,
                         url, sizeof(url), &written) != PK_OK) return nil;
    return [[[NSString alloc] initWithBytes:url length:written encoding:NSUTF8StringEncoding] autorelease];
}

/* a link the core refuses is dropped, it would reach the system browser unchecked */
- (NSArray *)linksFromSpan:(pk_span)span {
    pk_span hrefs[PK_STORY_MAX_LINKS];
    size_t count = pk_story_links(&_doc, span, hrefs, PK_STORY_MAX_LINKS);
    NSMutableArray *links = [NSMutableArray arrayWithCapacity:count];
    size_t index;
    for (index = 0; index < count; index++) {
        char url[PK_MAX_URL_BYTES];
        size_t written = 0;
        NSString *link;
        if (pk_url_normalize_link((const char *)_bytes.bytes + hrefs[index].offset, hrefs[index].length,
                                  url, sizeof(url), &written) != PK_OK) continue;
        link = [[[NSString alloc] initWithBytes:url length:written encoding:NSUTF8StringEncoding] autorelease];
        if (link && ![links containsObject:link]) [links addObject:link];
    }
    return links;
}

- (void)dealloc { [_bytes release]; [super dealloc]; }
@end

NSString *PKCompactScore(NSInteger value) {
    char text[32];
    size_t written = 0;
    if (pk_number_format((long)value, text, sizeof(text), &written) != PK_OK) return @"0";
    return [[[NSString alloc] initWithBytes:text length:written encoding:NSUTF8StringEncoding] autorelease];
}

/* presentation stays out of the core, the ids and counts come from there */
static NSString *PKReactionEmoji(long reactionID) {
    switch (reactionID) {
        case 1: return @"😂"; case 2: return @"😇"; case 3: return @"😮";
        case 4: return @"😢"; case 5: return @"😡"; case 6: return @"💯";
        case 7: return @"👏"; case 8: return @"🤡"; case 9: return @"😭";
        case 10: return @"🥺"; case 11: return @"🕊"; case 12: return @"🤦";
        case 13: return @"🔥"; case 14: return @"💔"; case 15: return @"❤️"; case 16: return @"😆";
        case 22: return @"🍿"; case 23: return @"😐"; case 24: return @"🍓"; case 25: return @"😳";
        case 28: return @"🥹"; case 29: return @"🙏"; case 35: return @"🎄";
        case 26: return @"💩"; case 27: return @"💀"; case 30: return @"🫠";
        case 33: return @"😤"; case 34: return @"🥳"; case 36: return @"🤔";
        case 37: return @"🤮"; case 38: return @"🤮"; case 39: return @"🪗";
        case 40: return @"🐔"; case 41: return @"💯"; case 42: return @"👌";
        default: return @"•";
    }
}

static NSArray *PKReactionArray(const pk_reaction *reactions, size_t count) {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:count];
    size_t index;
    for (index = 0; index < count; index++)
        [result addObject:[NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithLong:reactions[index].id], @"id",
            [NSNumber numberWithLong:reactions[index].count], @"count",
            PKReactionEmoji(reactions[index].id), @"emoji",
            [NSNumber numberWithBool:reactions[index].active ? YES : NO], @"active", nil]];
    return result;
}

NSString *PKReactionSummary(NSArray *reactions, NSUInteger limit) {
    NSMutableArray *parts;
    if (!reactions.count) return @"";
    parts = [NSMutableArray array];
    for (NSDictionary *reaction in reactions) {
        if (parts.count >= limit) break;
        [parts addObject:[NSString stringWithFormat:@"%@ %@", [reaction objectForKey:@"emoji"], [reaction objectForKey:@"count"]]];
    }
    return [parts componentsJoinedByString:@"   "];
}

NSArray *PKPostsFromHTML(NSString *html) {
    PKDocument *document = [PKDocument documentWithHTML:html];
    pk_post *raw;
    size_t count;
    size_t index;
    NSMutableArray *posts;
    if (!document) return [NSArray array];

    raw = calloc(PK_FEED_MAX_POSTS, sizeof(*raw));
    if (!raw) return [NSArray array];
    count = pk_feed_parse([document handle], raw, PK_FEED_MAX_POSTS);
    posts = [NSMutableArray arrayWithCapacity:count];
    for (index = 0; index < count; index++) {
        PKPost *post = [[PKPost alloc] init];
        NSMutableArray *tags = [NSMutableArray arrayWithCapacity:raw[index].tag_count];
        size_t tag;
        post.url = [document urlFromSpan:raw[index].url];
        post.title = [document textFromSpan:raw[index].title];
        post.storyID = [document rawFromSpan:raw[index].story_id];
        post.author = [document textFromSpan:raw[index].author] ?: @"Weeabu";
        post.date = [document textFromSpan:raw[index].date];
        post.imageURL = [document urlFromSpan:raw[index].image_url];
        post.avatarURL = [document urlFromSpan:raw[index].avatar_url];
        post.community = [document textFromSpan:raw[index].community];
        post.score = (NSInteger)raw[index].score;
        post.scoreKnown = raw[index].score_known ? YES : NO;
        {
            pk_reaction reactions[PK_REACTIONS_MAX];
            size_t reactionCount = pk_reactions_parse([document handle], raw[index].reactions, reactions, PK_REACTIONS_MAX);
            post.reactions = PKReactionArray(reactions, reactionCount);
        }
        post.comments = (NSInteger)raw[index].comments;
        post.hasVideo = raw[index].has_video ? YES : NO;
        for (tag = 0; tag < raw[index].tag_count; tag++) {
            NSString *text = [document textFromSpan:raw[index].tags[tag]];
            if (text.length) [tags addObject:text];
        }
        post.tags = tags;
        post.summary = tags.count ? [tags componentsJoinedByString:@" · "] : @"";
        {
            NSMutableArray *visible = [NSMutableArray array];
            NSMutableArray *all = [NSMutableArray array];
            NSMutableArray *media = [NSMutableArray array];
            size_t part;
            for (part = 0; part < raw[index].text_count; part++) {
                NSString *text = [document textFromSpan:raw[index].text_blocks[part]];
                if (!text.length) continue;
                [all addObject:text];
                if (part < raw[index].text_visible_count) [visible addObject:text];
            }
            for (part = 0; part < raw[index].media_count; part++) {
                NSString *mediaURL = [document urlFromSpan:raw[index].media[part].url];
                NSString *poster = [document urlFromSpan:raw[index].media[part].poster];
                NSString *duration = [document rawFromSpan:raw[index].media[part].duration];
                BOOL video = raw[index].media[part].type == PK_BLOCK_VIDEO;
                if (!mediaURL.length) continue;
                [media addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                    (video ? @"video" : @"image"), @"type",
                    mediaURL, @"url",
                    (poster.length ? poster : (video ? @"" : mediaURL)), @"poster",
                    (duration ?: @""), @"duration", nil]];
            }
            post.parentURL = [document urlFromSpan:raw[index].parent_url];
            post.parentTitle = PKParentTitle([document textFromSpan:raw[index].parent_title]);
            post.excerpt = [visible componentsJoinedByString:@"\n\n"];
            post.fullText = [all componentsJoinedByString:@"\n\n"];
            post.media = media;
            if (raw[index].media_width > 0 && raw[index].media_height > 0 && post.imageURL.length) {
                post.imageWidth = (double)raw[index].media_width;
                post.imageHeight = (double)raw[index].media_height;
            }
        }
/* a card whose link failed the url rules cannot be opened */
        if (post.url.length && post.title.length) [posts addObject:post];
        [post release];
    }
    free(raw);
    return posts;
}

/* the site words it "Ответ на пост «title»", the screens show the title only */
static NSString *PKParentTitle(NSString *label) {
    NSString *prefix = @"Ответ на пост «";
    if (!label.length) return nil;
    if ([label hasPrefix:prefix] && [label hasSuffix:@"»"] && label.length > prefix.length + 1)
        return [label substringWithRange:NSMakeRange(prefix.length, label.length - prefix.length - 1)];
    return label;
}

PKPost *PKParentPost(PKPost *post) {
    if (!post.parentURL.length) return nil;
    PKPost *parent = [[[PKPost alloc] init] autorelease];
    NSString *path = post.parentURL;
    NSRange query = [path rangeOfString:@"?"];
    if (query.location != NSNotFound) path = [path substringToIndex:query.location];
    NSRange underscore = [path rangeOfString:@"_" options:NSBackwardsSearch];
    NSString *tail = underscore.location == NSNotFound ? @"" : [path substringFromIndex:underscore.location + 1];
    BOOL digits = tail.length > 0;
    for (NSUInteger index = 0; index < tail.length; index++) {
        unichar c = [tail characterAtIndex:index];
        if (c < '0' || c > '9') { digits = NO; break; }
    }
    parent.url = post.parentURL;
    parent.title = post.parentTitle.length ? post.parentTitle : PKText(@"Исходный пост");
    parent.storyID = digits ? tail : nil;
    parent.author = @"";
    parent.tags = [NSArray array];
    return parent;
}

NSArray *PKStoryBlocksFromHTML(NSString *html) {
    PKDocument *document = [PKDocument documentWithHTML:html];
    pk_span content;
    pk_story_block blocks[PK_STORY_MAX_BLOCKS];
    size_t count;
    size_t index;
    NSMutableArray *result;
    if (!document || pk_story_content([document handle], &content) != PK_OK) return [NSArray array];

    count = pk_story_blocks([document handle], content, blocks, PK_STORY_MAX_BLOCKS);
    result = [NSMutableArray arrayWithCapacity:count];
    for (index = 0; index < count; index++) {
        if (blocks[index].type == PK_BLOCK_TEXT) {
            NSString *text = [document textFromSpan:blocks[index].text];
            if (text.length)
                [result addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"text", @"type", text, @"text",
                                   [document linksFromSpan:blocks[index].text], @"links", nil]];
            continue;
        }
        {
            NSString *url = [document urlFromSpan:blocks[index].url];
            NSString *poster = [document urlFromSpan:blocks[index].poster];
            NSString *duration = [document rawFromSpan:blocks[index].duration];
            if (!url.length) continue;
            [result addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                (blocks[index].type == PK_BLOCK_VIDEO ? @"video" : @"image"), @"type",
                url, @"url",
                (poster.length ? poster : (blocks[index].type == PK_BLOCK_VIDEO ? @"" : url)), @"poster",
                (duration.length ? duration : @""), @"duration",
                [NSNumber numberWithLong:blocks[index].width], @"width",
                [NSNumber numberWithLong:blocks[index].height], @"height", nil]];
        }
    }
    return result;
}

NSArray *PKStoryReactionsFromHTML(NSString *html) {
    PKDocument *document = [PKDocument documentWithHTML:html];
    pk_reaction reactions[PK_REACTIONS_MAX];
    size_t count = 0;
    if (!document) return [NSArray array];
    if (pk_story_reactions([document handle], reactions, PK_REACTIONS_MAX, &count) != PK_OK) return [NSArray array];
    return PKReactionArray(reactions, count);
}

BOOL PKStoryScoreFromHTML(NSString *html, NSInteger *score) {
    PKDocument *document = [PKDocument documentWithHTML:html];
    long value = 0;
    if (score) *score = 0;
    if (!score || !document || pk_story_score([document handle], &value) != PK_OK) return NO;
    *score = (NSInteger)value;
    return YES;
}

NSString *PKCSRFTokenFromHTML(NSString *html) {
    PKDocument *document = [PKDocument documentWithHTML:html];
    pk_span token;
    if (!document || pk_story_csrf([document handle], &token) != PK_OK) return nil;
    return [document rawFromSpan:token];
}

NSArray *PKCommentsFromHTML(NSString *html) {
    PKDocument *document = [PKDocument documentWithHTML:html];
    pk_comment *raw;
    size_t count;
    size_t index;
    NSMutableArray *comments;
    if (!document) return [NSArray array];

    raw = calloc(PK_COMMENTS_MAX, sizeof(*raw));
    if (!raw) return [NSArray array];
    count = pk_comments_parse([document handle], raw, PK_COMMENTS_MAX);
    comments = [NSMutableArray arrayWithCapacity:count];
    for (index = 0; index < count; index++) {
        PKComment *comment = [[PKComment alloc] init];
        pk_reaction reactions[PK_REACTIONS_MAX];
        size_t reaction_count;
        comment.commentID = [document rawFromSpan:raw[index].comment_id] ?: @"";
        comment.parentID = [document rawFromSpan:raw[index].parent_id] ?: @"";
        comment.author = [document textFromSpan:raw[index].author] ?: @"Weeabu";
        comment.body = [document textFromSpan:raw[index].body] ?: @"";
        comment.date = [document textFromSpan:raw[index].date] ?: @"";
        comment.mediaURL = [document urlFromSpan:raw[index].media_url];
        comment.links = [document linksFromSpan:raw[index].body];
        comment.avatarURL = [document urlFromSpan:raw[index].avatar_url];
        comment.score = (NSInteger)raw[index].score;
        comment.scoreKnown = raw[index].score_known ? YES : NO;
        comment.scoreHidden = raw[index].score_hidden ? YES : NO;
        comment.indent = (NSInteger)raw[index].indent;
        comment.mediaIsSticker = raw[index].media_is_sticker ? YES : NO;
        reaction_count = pk_reactions_parse([document handle], raw[index].reactions, reactions, PK_REACTIONS_MAX);
        comment.reactions = PKReactionArray(reactions, reaction_count);
        [comments addObject:comment];
        [comment release];
    }
    free(raw);
    return comments;
}

NSArray *PKCommentIDsFromHTML(NSString *html) {
    PKDocument *document = [PKDocument documentWithHTML:html];
    long *ids;
    size_t count;
    size_t index;
    NSMutableArray *result;
    if (!document) return [NSArray array];

    ids = calloc(PK_COMMENTS_MAX, sizeof(*ids));
    if (!ids) return [NSArray array];
    count = pk_comments_tree_ids([document handle], ids, PK_COMMENTS_MAX);
    result = [NSMutableArray arrayWithCapacity:count];
    for (index = 0; index < count; index++)
        [result addObject:[NSNumber numberWithLong:ids[index]]];
    free(ids);
    return result;
}

void PKAppendUniquePosts(NSMutableArray *destination, NSArray *posts) {
    NSMutableSet *urls;
    if (!destination || ![posts isKindOfClass:[NSArray class]]) return;
    urls = [NSMutableSet set];
    for (PKPost *post in destination)
        if ([post isKindOfClass:[PKPost class]] && post.url.length) [urls addObject:post.url];
    for (PKPost *post in posts) {
        if (![post isKindOfClass:[PKPost class]] || !post.url.length || [urls containsObject:post.url]) continue;
        [destination addObject:post];
        [urls addObject:post.url];
    }
}
