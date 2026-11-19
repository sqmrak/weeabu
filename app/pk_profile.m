#import "pk_profile.h"
#import "pk_v1.h"
#import "pk_http.h"
#import "pk_lang.h"
#import "pk_auth.h"
#import "pk_dialog.h"
#include "pk_text.h"
#include <string.h>

static NSString *PKProfileString(id value) {
    return [value isKindOfClass:[NSString class]] ? value : @"";
}

static NSInteger PKProfileCount(id value) {
    if ([value isKindOfClass:[NSNumber class]] && CFGetTypeID((CFTypeRef)value) != CFBooleanGetTypeID()) return [value integerValue];
    if ([value isKindOfClass:[NSString class]]) return [value integerValue];
    return 0;
}

/* the loader refuses a picture address that is not https, so the profile should not carry it */
static NSString *PKProfileImageURL(id value) {
    NSString *text = PKProfileString(value);
    return [text hasPrefix:@"https://"] ? text : @"";
}

@implementation PKAward
@synthesize title = _title, imageURL = _imageURL, date = _date, storyTitle = _storyTitle, link = _link;
- (void)dealloc { [_title release]; [_imageURL release]; [_date release]; [_storyTitle release]; [_link release]; [super dealloc]; }
@end

@implementation PKCommunity
@synthesize name = _name, link = _link, avatarURL = _avatarURL;
- (void)dealloc { [_name release]; [_link release]; [_avatarURL release]; [super dealloc]; }
@end

@implementation PKUserProfile
@synthesize userID = _userID, name = _name, avatarURL = _avatarURL, headerURL = _headerURL, approved = _approved, about = _about;
@synthesize rating = _rating, registration = _registration, ratingNegative = _ratingNegative, comments = _comments, stories = _stories;
@synthesize subscribed = _subscribed, ignored = _ignored, hotStories = _hotStories, pluses = _pluses, minuses = _minuses, subscribers = _subscribers, awards = _awards, communities = _communities;

+ (PKUserProfile *)profileFromResponse:(id)response {
    NSDictionary *user = [response isKindOfClass:[NSDictionary class]] ? [response objectForKey:@"user"] : nil;
    if (![user isKindOfClass:[NSDictionary class]]) return nil;
    NSString *name = PKProfileString([user objectForKey:@"user_name"]);
    if (!name.length) return nil;
    PKUserProfile *profile = [[[PKUserProfile alloc] init] autorelease];
    profile.name = name;
    profile.userID = [NSNumber numberWithInteger:PKProfileCount([user objectForKey:@"user_id"])];
    profile.avatarURL = PKProfileImageURL([user objectForKey:@"avatar"]);
    profile.headerURL = PKProfileImageURL([user objectForKey:@"header_bg_url"]);
    profile.approved = PKProfileString([user objectForKey:@"approved"]);
    profile.about = [PKProfileString([user objectForKey:@"about"]) stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    profile.registration = PKProfileString([user objectForKey:@"registration_duration"]);
    id value = [user objectForKey:@"rating"];
    NSString *rating = [value isKindOfClass:[NSString class]] ? value : ([value isKindOfClass:[NSNumber class]] ? [value stringValue] : nil);
    int negative = 0;
    const char *bytes = rating.length && rating.length <= 32 ? [rating UTF8String] : NULL;
    if (bytes && pk_profile_rating(bytes, strlen(bytes), &negative)) {
        profile.rating = rating;
        profile.ratingNegative = negative != 0;
    }
    profile.comments = PKProfileCount([user objectForKey:@"comments_count"]);
    profile.stories = PKProfileCount([user objectForKey:@"stories_count"]);
    profile.hotStories = PKProfileCount([user objectForKey:@"stories_hot_count"]);
    profile.pluses = PKProfileCount([user objectForKey:@"pluses_count"]);
    profile.minuses = PKProfileCount([user objectForKey:@"minuses_count"]);
    profile.subscribers = PKProfileCount([user objectForKey:@"subscribers_count"]);
    NSMutableArray *awards = [NSMutableArray array];
    id rawAwards = [user objectForKey:@"awards"];
    if ([rawAwards isKindOfClass:[NSArray class]]) for (id item in rawAwards) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        if ([PKProfileString([item objectForKey:@"is_hidden"]) isEqualToString:@"1"]) continue;
        PKAward *award = [[[PKAward alloc] init] autorelease];
        award.title = PKProfileString([item objectForKey:@"award_title"]);
        award.imageURL = PKProfileImageURL([item objectForKey:@"award_image"]);
        award.date = PKProfileString([item objectForKey:@"date"]);
        award.storyTitle = PKProfileString([item objectForKey:@"story_title"]);
        NSString *link = PKProfileString([item objectForKey:@"link"]);
        award.link = [link hasPrefix:@"/story/"] ? link : @"";
        if (award.title.length) [awards addObject:award];
    }
    profile.awards = awards;
    NSMutableArray *communities = [NSMutableArray array];
    id rawCommunities = [user objectForKey:@"communities"];
    if ([rawCommunities isKindOfClass:[NSArray class]]) for (id item in rawCommunities) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        PKCommunity *community = [[[PKCommunity alloc] init] autorelease];
        community.name = PKProfileString([item objectForKey:@"name"]);
        community.link = PKProfileString([item objectForKey:@"link"]);
        community.avatarURL = PKProfileImageURL([item objectForKey:@"avatar_url"]);
        if (!community.avatarURL.length) community.avatarURL = PKProfileImageURL([item objectForKey:@"avatar"]);
        if (community.name.length && community.link.length) [communities addObject:community];
    }
    profile.communities = communities;
    profile.subscribed = [[user objectForKey:@"is_subscribed"] respondsToSelector:@selector(boolValue)] && [[user objectForKey:@"is_subscribed"] boolValue];
    profile.ignored = [[user objectForKey:@"is_ignored"] respondsToSelector:@selector(boolValue)] && [[user objectForKey:@"is_ignored"] boolValue];
    return profile;
}

- (NSString *)pageURL {
    return [@"https://pikabu.ru/@" stringByAppendingString:PKHTTPPercentEncode(_name ?: @"")];
}

- (void)dealloc {
    [_userID release]; [_name release]; [_avatarURL release]; [_headerURL release]; [_approved release]; [_about release];
    [_rating release]; [_registration release]; [_awards release]; [_communities release];
    [super dealloc];
}
@end

void PKLoadUserProfile(NSString *username, PKProfileCompletion completion) {
    PKV1Profile(username, nil, ^(id response, NSError *error) {
        PKUserProfile *profile = error ? nil : [PKUserProfile profileFromResponse:response];
        if (!error && !profile)
            error = [NSError errorWithDomain:@"WeeabuProfile" code:422 userInfo:
                     [NSDictionary dictionaryWithObject:PKText(@"Пикабу вернул профиль в неожиданном виде") forKey:NSLocalizedDescriptionKey]];
        if (completion) completion(profile, error);
    });
}

void PKLoadUserPosts(NSString *username, NSInteger page, PKPostsCompletion completion) {
    if (!username.length) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, [NSError errorWithDomain:@"WeeabuProfile" code:400 userInfo:[NSDictionary dictionaryWithObject:@"author name is empty" forKey:NSLocalizedDescriptionKey]]);
        });
        return;
    }
    NSString *url = [NSString stringWithFormat:@"https://pikabu.ru/@%@?page=%ld", PKHTTPPercentEncode(username), (long)page];
    PKHTTPGet(url, ^(NSData *data, NSError *error) {
        NSArray *posts = error ? nil : PKPostsFromHTML(PKHTTPText(data));
        if (!error && !data.length)
            error = [NSError errorWithDomain:@"WeeabuProfile" code:2 userInfo:[NSDictionary dictionaryWithObject:PKText(@"Пикабу вернул пустой ответ") forKey:NSLocalizedDescriptionKey]];
        if (completion) completion(posts, error);
    });
}

NSString *PKPlainTextFromHTML(NSString *html) {
    if (![html isKindOfClass:[NSString class]] || !html.length) return @"";
    const char *bytes = [html UTF8String];
    size_t length = bytes ? strlen(bytes) : 0;
    if (!length) return @"";
    /* stripping markup and decoding entities only shortens the bytes */
    char *out = (char *)malloc(length + 1);
    if (!out) return @"";
    size_t written = 0;
    pk_status status = pk_text_plain(bytes, length, out, length + 1, &written);
    NSString *text = status == PK_OK ? [[[NSString alloc] initWithBytes:out length:written encoding:NSUTF8StringEncoding] autorelease] : nil;
    free(out);
    return [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: @"";
}

static NSError *PKProfileError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"WeeabuProfile" code:code userInfo:[NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey]];
}

static BOOL PKValidID(NSNumber *value) {
    return [value isKindOfClass:[NSNumber class]] && [value longLongValue] > 0;
}

static NSString *PKCachedUserName;
static NSNumber *PKCachedUserID;

void PKCurrentUserID(void (^completion)(NSNumber *userID, NSError *error)) {
    NSString *name = PKSessionUsername();
    if (!name.length) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, PKProfileError(401, PKText(@"Войдите в аккаунт"))); });
        return;
    }
    if (PKCachedUserID && [PKCachedUserName isEqualToString:name]) {
        NSNumber *cached = [[PKCachedUserID retain] autorelease];
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(cached, nil); });
        return;
    }
    PKLoadUserProfile(name, ^(PKUserProfile *profile, NSError *error) {
        if (!error && !PKValidID(profile.userID)) error = PKProfileError(422, PKText(@"Не удалось узнать номер аккаунта"));
        if (!error) {
            [PKCachedUserName release]; PKCachedUserName = [name copy];
            [PKCachedUserID release]; PKCachedUserID = [profile.userID retain];
        }
        if (completion) completion(error ? nil : profile.userID, error);
    });
}

static void PKUserAction(NSString *method, NSString *targetKey, NSNumber *target, BOOL add, void (^completion)(NSError *error)) {
    if (!PKValidID(target)) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(PKProfileError(400, @"invalid author id")); });
        return;
    }
    PKCurrentUserID(^(NSNumber *userID, NSError *error) {
        if (error) { if (completion) completion(error); return; }
        NSDictionary *fields = [NSDictionary dictionaryWithObjectsAndKeys:userID, @"user_id", target, targetKey, add ? @"add" : @"remove", @"action", nil];
        PKV1Action(method, fields, completion);
    });
}

void PKSetSubscribed(NSNumber *authorID, BOOL subscribed, void (^completion)(NSError *error)) {
    PKUserAction(@"user.subscribe.set", @"subscribe_user_id", authorID, subscribed, completion);
}

void PKSetIgnored(NSNumber *authorID, BOOL ignored, void (^completion)(NSError *error)) {
    PKUserAction(@"user.ignored.set", @"ignore_user_id", authorID, ignored, completion);
}

void PKPromptApiSession(void (^completion)(BOOL opened)) {
    PKShowPasswordPrompt(PKText(@"Подтвердите вход"), PKText(@"Подписки, комментарии и уведомления идут через API, которому нужен отдельный вход. Пароль нигде не сохраняется."), PKText(@"Войти"), ^(NSString *password) {
        if (!password.length) { if (completion) completion(NO); return; }
        PKV1Reauthenticate(password, ^(NSError *error) {
            if (error) PKShowNotice(PKText(@"Не удалось войти"), error.localizedDescription);
            if (completion) completion(error == nil);
        });
    });
}

@implementation PKMyComment
@synthesize text = _text, storyTitle = _storyTitle, storyURL = _storyURL, storyID = _storyID, commentID = _commentID, parentAuthor = _parentAuthor, parentText = _parentText;
@synthesize time = _time, rating = _rating;
- (void)dealloc { [_text release]; [_storyTitle release]; [_storyURL release]; [_storyID release]; [_commentID release]; [_parentAuthor release]; [_parentText release]; [super dealloc]; }
@end

static NSString *PKCommentText(NSDictionary *comment) {
    id desc = [comment objectForKey:@"comment_desc"];
    NSString *text = [desc isKindOfClass:[NSDictionary class]] ? PKProfileString([desc objectForKey:@"text"]) : @"";
    NSString *plain = PKPlainTextFromHTML(text);
    if (plain.length) return plain;
    NSArray *images = [desc isKindOfClass:[NSDictionary class]] ? [desc objectForKey:@"images"] : nil;
    return [images isKindOfClass:[NSArray class]] && images.count ? PKText(@"[изображение]") : @"";
}

void PKLoadMyComments(NSNumber *userID, NSInteger sort, NSInteger page, void (^completion)(NSArray *comments, NSError *error)) {
    if (!PKValidID(userID) || page < 1 || (sort != 1 && sort != 2)) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, PKProfileError(400, @"invalid comments request")); });
        return;
    }
    NSDictionary *fields = [NSDictionary dictionaryWithObjectsAndKeys:userID, @"user_id", [NSNumber numberWithInteger:sort], @"sort", [NSNumber numberWithInteger:page], @"page", nil];
    PKV1Request(@"user.commented.get", fields, ^(id response, NSError *error) {
        if (error) { if (completion) completion(nil, error); return; }
        id data = [response isKindOfClass:[NSDictionary class]] ? [response objectForKey:@"data"] : nil;
        if (![data isKindOfClass:[NSArray class]]) {
            if (completion) completion(nil, PKProfileError(422, PKText(@"Пикабу вернул комментарии в неожиданном виде")));
            return;
        }
        NSMutableArray *result = [NSMutableArray array];
        for (id item in data) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *comment = [item objectForKey:@"comment"];
            if (![comment isKindOfClass:[NSDictionary class]]) continue;
            PKMyComment *mine = [[[PKMyComment alloc] init] autorelease];
            mine.text = PKCommentText(comment);
            mine.storyTitle = PKProfileString([comment objectForKey:@"story_title"]);
            NSString *url = PKProfileString([comment objectForKey:@"story_url"]);
            mine.storyURL = [url hasPrefix:@"https://pikabu.ru/story/"] ? url : @"";
            mine.storyID = [NSString stringWithFormat:@"%ld", (long)PKProfileCount([comment objectForKey:@"story_id"])];
            NSInteger commentNumber = PKProfileCount([comment objectForKey:@"comment_id"]);
            mine.commentID = commentNumber > 0 ? [NSString stringWithFormat:@"%ld", (long)commentNumber] : @"";
            mine.time = (long)PKProfileCount([comment objectForKey:@"comment_time"]);
            mine.rating = PKProfileCount([comment objectForKey:@"comment_rating"]);
            NSDictionary *parent = [item objectForKey:@"parent_data"];
            if ([parent isKindOfClass:[NSDictionary class]]) {
                mine.parentAuthor = PKProfileString([parent objectForKey:@"user_name"]);
                mine.parentText = PKCommentText(parent);
            }
            [result addObject:mine];
        }
        if (completion) completion(result, nil);
    });
}

@implementation PKNotice
@synthesize text = _text, date = _date, type = _type, isNew = _isNew;
- (void)dealloc { [_text release]; [_date release]; [_type release]; [super dealloc]; }
@end

void PKLoadNotifications(NSNumber *userID, void (^completion)(NSArray *notices, NSError *error)) {
    if (!PKValidID(userID)) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, PKProfileError(400, @"invalid user id")); });
        return;
    }
    PKV1Request(@"user.notification.get", [NSDictionary dictionaryWithObject:userID forKey:@"user_id"], ^(id response, NSError *error) {
        if (error) { if (completion) completion(nil, error); return; }
        /* the 1.17 client reads an array, a wrapper object with the array under "data" is accepted too */
        id items = [response isKindOfClass:[NSArray class]] ? response : ([response isKindOfClass:[NSDictionary class]] ? [response objectForKey:@"data"] : nil);
        if (![items isKindOfClass:[NSArray class]]) {
            if (completion) completion(nil, PKProfileError(422, PKText(@"Пикабу вернул уведомления в неожиданном виде")));
            return;
        }
        NSMutableArray *result = [NSMutableArray array];
        for (id item in items) {
            if (![item isKindOfClass:[NSDictionary class]]) continue;
            PKNotice *notice = [[[PKNotice alloc] init] autorelease];
            notice.text = PKPlainTextFromHTML(PKProfileString([item objectForKey:@"text"]));
            notice.date = PKProfileString([item objectForKey:@"datetime"]);
            notice.type = PKProfileString([item objectForKey:@"type"]);
            id fresh = [item objectForKey:@"is_new"];
            notice.isNew = [fresh respondsToSelector:@selector(boolValue)] && [fresh boolValue];
            if (notice.text.length) [result addObject:notice];
        }
        if (completion) completion(result, nil);
    });
}

void PKNotificationAction(NSNumber *userID, NSString *action, void (^completion)(NSError *error)) {
    if (!PKValidID(userID) || !([action isEqualToString:@"mark_as_read"] || [action isEqualToString:@"remove_all"])) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(PKProfileError(400, @"invalid notification action")); });
        return;
    }
    PKV1Action(@"user.notification.set", [NSDictionary dictionaryWithObjectsAndKeys:userID, @"user_id", action, @"action", nil], completion);
}
