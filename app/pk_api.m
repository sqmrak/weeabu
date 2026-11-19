#import "pk_api.h"
#import "pk_lang.h"
#import "pk_http.h"
#import "pk_v1.h"
#import <CoreFoundation/CoreFoundation.h>
#include "pk_settings.h"
#include "pk_text.h"
#include <string.h>

static NSError *PKAPIError(NSData *data) {
    if (!data.length) return [NSError errorWithDomain:@"PikabuAPI" code:1 userInfo:[NSDictionary dictionaryWithObject:@"server returned an empty response" forKey:NSLocalizedDescriptionKey]];
    NSError *jsonError = nil;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:&jsonError];
    NSDictionary *response = [json isKindOfClass:[NSDictionary class]] ? json : nil;
    NSDictionary *nested = [response objectForKey:@"response"];
    if ([nested isKindOfClass:[NSDictionary class]]) response = nested;
    if (![response isKindOfClass:[NSDictionary class]] || ![[response objectForKey:@"result"] isKindOfClass:[NSNumber class]])
        return [NSError errorWithDomain:@"PikabuAPI" code:2 userInfo:[NSDictionary dictionaryWithObject:@"server returned an unsupported response" forKey:NSLocalizedDescriptionKey]];
    if (![[response objectForKey:@"result"] boolValue]) {
        id rawMessage = [response objectForKey:@"message"];
        NSString *message = [rawMessage isKindOfClass:[NSString class]] ? rawMessage : nil;
        return [NSError errorWithDomain:@"PikabuAPI" code:1 userInfo:[NSDictionary dictionaryWithObject:(message.length ? message : @"request failed") forKey:NSLocalizedDescriptionKey]];
    }
    return nil;
}

static void PKLoadCommentBatch(NSArray *identifiers, NSUInteger offset, NSString *csrfToken,
                               NSMutableArray *comments, PKCommentsCompletion completion) {
    if (offset >= identifiers.count) {
        if (completion) completion(comments, nil);
        return;
    }
    NSUInteger count = MIN((NSUInteger)50, identifiers.count - offset);
    NSArray *batch = [identifiers subarrayWithRange:NSMakeRange(offset, count)];
    NSMutableArray *parts = [NSMutableArray arrayWithCapacity:count];
    for (NSNumber *identifier in batch) [parts addObject:[identifier stringValue]];
    NSDictionary *fields = [NSDictionary dictionaryWithObjectsAndKeys:
        @"get_comments_by_ids", @"action", [parts componentsJoinedByString:@","], @"ids", nil];
    PKHTTPPost(@"https://pikabu.ru/ajax/comments_actions.php", fields, csrfToken, ^(NSData *data, NSError *error) {
        if (!error) error = PKAPIError(data);
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        NSArray *items = [json isKindOfClass:[NSDictionary class]] && [[json objectForKey:@"data"] isKindOfClass:[NSArray class]] ? [json objectForKey:@"data"] : nil;
        if (!error && !items) error = [NSError errorWithDomain:@"PikabuAPI" code:6 userInfo:[NSDictionary dictionaryWithObject:@"comments response has an unsupported format" forKey:NSLocalizedDescriptionKey]];
        if (error) {
            if (completion) completion(comments, error);
            return;
        }
        for (NSDictionary *item in items) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            NSString *fragment = [item objectForKey:@"html"];
            if ([fragment isKindOfClass:[NSString class]]) [comments addObjectsFromArray:PKCommentsFromHTML(fragment)];
        }
        PKLoadCommentBatch(identifiers, offset + count, csrfToken, comments, completion);
    });
}

static NSError *PKActionInputError(NSString *identifier, NSString *csrfToken) {
    if (![identifier length]) return [NSError errorWithDomain:@"PikabuAPI" code:3 userInfo:[NSDictionary dictionaryWithObject:@"publication identifier is missing" forKey:NSLocalizedDescriptionKey]];
    if (![csrfToken length]) return [NSError errorWithDomain:@"PikabuAPI" code:4 userInfo:[NSDictionary dictionaryWithObject:@"session token is missing, reload the publication and sign in again" forKey:NSLocalizedDescriptionKey]];
    return nil;
}

void PKLoadFeed(NSString *section, NSInteger page, PKPostsCompletion completion) {
    NSString *url = [NSString stringWithFormat:@"https://pikabu.ru/%@?page=%ld", section, (long)page];
    PKHTTPGet(url, ^(NSData *data, NSError *error) {
        NSArray *posts = PKPostsFromHTML(PKHTTPText(data));
        if (!error && (!data.length || (page == 1 && !posts.count))) error = [NSError errorWithDomain:@"PikabuAPI" code:2 userInfo:[NSDictionary dictionaryWithObject:PKText(@"Weeabu вернул пустую или неподдерживаемую страницу") forKey:NSLocalizedDescriptionKey]];
        if (completion) completion(posts, error);
    });
}

void PKSearch(NSString *query, NSInteger page, PKPostsCompletion completion) {
    NSString *url = [NSString stringWithFormat:@"https://pikabu.ru/search/?q=%@&page=%ld", PKHTTPPercentEncode(query), (long)page];
    PKHTTPGet(url, ^(NSData *data, NSError *error) {
        NSArray *posts = PKPostsFromHTML(PKHTTPText(data));
        if (!error && !data.length) error = [NSError errorWithDomain:@"PikabuAPI" code:5 userInfo:[NSDictionary dictionaryWithObject:PKText(@"Weeabu вернул пустой ответ") forKey:NSLocalizedDescriptionKey]];
        if (completion) completion(posts, error);
    });
}

void PKLoadStory(PKPost *post, PKStoryCompletion completion) {
    PKHTTPGet(post.url, ^(NSData *data, NSError *error) {
        NSString *html = PKHTTPText(data);
        if (completion) completion(html, error);
    });
}

void PKLoadComments(PKPost *post, NSString *storyHTML, PKCommentsCompletion completion) {
    (void)post;
    NSArray *identifiers = PKCommentIDsFromHTML(storyHTML);
    NSArray *embedded = PKCommentsFromHTML(storyHTML);
    if (!identifiers.count) {
        if (completion) completion(embedded, nil);
        return;
    }
    NSString *csrfToken = PKCSRFTokenFromHTML(storyHTML);
    NSError *inputError = PKActionInputError([[identifiers objectAtIndex:0] stringValue], csrfToken);
    if (inputError) { if (completion) completion(nil, inputError); return; }
    PKLoadCommentBatch(identifiers, 0, csrfToken, [NSMutableArray array], completion);
}

static NSNumber *PKPublicID(id raw) {
    if (![raw isKindOfClass:[NSString class]] && ![raw isKindOfClass:[NSNumber class]]) return nil;
    if ([raw isKindOfClass:[NSNumber class]] && CFGetTypeID((CFTypeRef)raw) == CFBooleanGetTypeID()) return nil;
    NSString *text = [raw isKindOfClass:[NSString class]] ? raw : [raw stringValue];
    const char *bytes = text.length <= 10 ? [text UTF8String] : NULL;
    long number = 0;
    if (!bytes || !pk_settings_user_id(bytes, strlen(bytes), &number)) return nil;
    return [NSNumber numberWithLong:number];
}

static NSNumber *PKPublicScore(id raw) {
    if (![raw isKindOfClass:[NSString class]] && ![raw isKindOfClass:[NSNumber class]]) return nil;
    if ([raw isKindOfClass:[NSNumber class]] && CFGetTypeID((CFTypeRef)raw) == CFBooleanGetTypeID()) return nil;
    NSString *text = [raw isKindOfClass:[NSString class]] ? raw : [raw stringValue];
    const char *bytes = text.length <= 32 ? [text UTF8String] : NULL;
    long number = 0;
    if (!bytes || pk_number_compact(bytes, strlen(bytes), &number) != PK_OK) return nil;
    return [NSNumber numberWithLong:number];
}

static NSError *PKCommentScoresError(void) {
    return [NSError errorWithDomain:@"PikabuAPI" code:7 userInfo:[NSDictionary dictionaryWithObject:@"comment ratings are unavailable" forKey:NSLocalizedDescriptionKey]];
}

static void PKLoadScorePage(NSNumber *storyID, NSInteger page, NSMutableSet *pending, BOOL invalidID, PKCommentScoresCompletion completion) {
    PKV1Story(storyID, page, ^(id response, NSError *error) {
        if (error) { if (completion) completion(nil, YES, error); return; }
        id story = [response isKindOfClass:[NSDictionary class]] ? [response objectForKey:@"story"] : nil;
        id rows = [response isKindOfClass:[NSDictionary class]] ? [response objectForKey:@"comments"] : nil;
        id more = [response isKindOfClass:[NSDictionary class]] ? [response objectForKey:@"has_next_page_comments"] : nil;
        NSNumber *actualID = [story isKindOfClass:[NSDictionary class]] ? PKPublicID([story objectForKey:@"story_id"]) : nil;
        if (![actualID isEqualToNumber:storyID] || ![rows isKindOfClass:[NSArray class]] || [rows count] > 400 ||
            ![more isKindOfClass:[NSNumber class]] || ([more integerValue] != 0 && [more integerValue] != 1)) {
            if (completion) completion(nil, YES, PKCommentScoresError());
            return;
        }
        NSMutableDictionary *scores = [NSMutableDictionary dictionary];
        for (id row in rows) {
            if (![row isKindOfClass:[NSDictionary class]]) continue;
            NSNumber *identifier = PKPublicID([row objectForKey:@"comment_id"]);
            NSString *key = [identifier stringValue];
            if (!key || ![pending containsObject:key]) continue;
            NSNumber *value = PKPublicScore([row objectForKey:@"comment_rating"]);
            if (!value) continue;
            [scores setObject:value forKey:key];
            [pending removeObject:key];
        }
        BOOL finished = !pending.count || ![more boolValue] || ![rows count] || page >= 4;
        NSError *remaining = finished && (pending.count || invalidID) ? PKCommentScoresError() : nil;
        if (completion) completion(scores, finished, remaining);
        if (!finished) PKLoadScorePage(storyID, page + 1, pending, invalidID, completion);
    });
}

void PKLoadHiddenCommentScores(PKPost *post, NSArray *comments, PKCommentScoresCompletion completion) {
    NSMutableSet *pending = [NSMutableSet set];
    BOOL invalidID = NO;
    for (PKComment *comment in comments) {
        if (![comment isKindOfClass:[PKComment class]] || !comment.scoreHidden || comment.scoreKnown) continue;
        NSNumber *identifier = PKPublicID(comment.commentID);
        if (identifier) [pending addObject:[identifier stringValue]];
        else invalidID = YES;
    }
    if (!pending.count) { if (completion) completion(nil, YES, invalidID ? PKCommentScoresError() : nil); return; }
    NSNumber *storyID = PKPublicID(post.storyID);
    if (!storyID) { if (completion) completion(nil, YES, PKCommentScoresError()); return; }
    PKLoadScorePage(storyID, 1, pending, invalidID, completion);
}

void PKVoteStory(PKPost *post, NSInteger vote, NSString *storyHTML, PKActionCompletion completion) {
    NSString *csrfToken = PKCSRFTokenFromHTML(storyHTML);
    NSError *inputError = PKActionInputError(post.storyID, csrfToken);
    if (inputError) { if (completion) completion(inputError); return; }
    NSDictionary *fields = [NSDictionary dictionaryWithObjectsAndKeys:post.storyID, @"story_id", [NSString stringWithFormat:@"%ld", (long)vote], @"vote", nil];
    PKHTTPPost(@"https://pikabu.ru/ajax/vote_story.php", fields, csrfToken, ^(NSData *data, NSError *error) {
        if (!error) error = PKAPIError(data);
        if (completion) completion(error);
    });
}

void PKVoteComment(PKComment *comment, NSInteger vote, NSString *storyHTML, PKActionCompletion completion) {
    NSString *csrfToken = PKCSRFTokenFromHTML(storyHTML);
    NSError *inputError = PKActionInputError(comment.commentID, csrfToken);
    if (inputError) { if (completion) completion(inputError); return; }
    NSDictionary *fields = [NSDictionary dictionaryWithObjectsAndKeys:comment.commentID, @"comment_id", [NSString stringWithFormat:@"%ld", (long)vote], @"vote", nil];
    PKHTTPPost(@"https://pikabu.ru/ajax/vote_comment.php", fields, csrfToken, ^(NSData *data, NSError *error) { if (!error) error = PKAPIError(data); if (completion) completion(error); });
}

void PKReactStory(PKPost *post, NSInteger reactionID, BOOL add, NSString *storyHTML, PKActionCompletion completion) {
    NSString *csrfToken = PKCSRFTokenFromHTML(storyHTML);
    NSError *inputError = PKActionInputError(post.storyID, csrfToken);
    if (inputError) { if (completion) completion(inputError); return; }
    NSDictionary *fields = [NSDictionary dictionaryWithObjectsAndKeys:post.storyID, @"story_id", [NSString stringWithFormat:@"%ld", (long)reactionID], @"type", add ? @"1" : @"0", @"state", nil];
    PKHTTPPost(@"https://pikabu.ru/ajax/save_emotion.php", fields, csrfToken, ^(NSData *data, NSError *error) { if (!error) error = PKAPIError(data); if (completion) completion(error); });
}

void PKReactComment(PKComment *comment, NSInteger reactionID, BOOL add, NSString *storyHTML, PKActionCompletion completion) {
    NSString *csrfToken = PKCSRFTokenFromHTML(storyHTML);
    NSError *inputError = PKActionInputError(comment.commentID, csrfToken);
    if (inputError) { if (completion) completion(inputError); return; }
    NSDictionary *fields = [NSDictionary dictionaryWithObjectsAndKeys:@"user-comment-emotions/save", @"route", comment.commentID, @"comment_id", [NSString stringWithFormat:@"%ld", (long)reactionID], @"type", add ? @"1" : @"0", @"state", nil];
    PKHTTPPost(@"https://pikabu.ru/ajax.php", fields, csrfToken, ^(NSData *data, NSError *error) { if (!error) error = PKAPIError(data); if (completion) completion(error); });
}
