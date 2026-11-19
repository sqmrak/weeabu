#import "pk_v1.h"
#import "pk_http.h"
#import "pk_v1_signature.h"
#import "pk_text.h"
#import "pk_auth.h"
#import <CoreFoundation/CoreFoundation.h>
#include <mbedtls/md5.h>
#include <string.h>

static NSString * const PKV1ErrorDomain = @"WeeabuV1";

static NSError *PKV1Error(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:PKV1ErrorDomain code:code userInfo:
            [NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey]];
}

static NSString *PKV1DeviceID(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    @synchronized (defaults) {
        NSString *value = [defaults stringForKey:@"pk_v1_device_id"];
        if (value.length) return value;
        CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
        if (!uuid) return nil;
        value = [(NSString *)CFUUIDCreateString(kCFAllocatorDefault, uuid) autorelease];
        CFRelease(uuid);
        if (value.length) [defaults setObject:value forKey:@"pk_v1_device_id"];
        return value;
    }
}

static BOOL PKV1AddScalar(id value, NSMutableArray *values) {
    if (value == [NSNull null]) return YES;
    if ([value isKindOfClass:[NSString class]]) {
        [values addObject:value];
        return YES;
    }
    if ([value isKindOfClass:[NSNumber class]]) {
        if (CFGetTypeID((CFTypeRef)value) == CFBooleanGetTypeID())
            [values addObject:[value boolValue] ? @"true" : @"false"];
        else [values addObject:[value stringValue]];
        return YES;
    }
    return NO;
}

static NSComparisonResult PKV1Compare(id left, id right, void *context) {
    (void)context;
    return [left compare:right options:NSLiteralSearch];
}

static NSDictionary *PKV1Build(NSString *method, NSDictionary *parameters, NSError **error) {
    if (![method isKindOfClass:[NSString class]] || !method.length || method.length > 128 ||
        [method rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789._"] invertedSet]].location != NSNotFound ||
        ![parameters isKindOfClass:[NSDictionary class]] || parameters.count > 128) {
        *error = PKV1Error(400, @"invalid api method or parameters"); return nil;
    }
    NSMutableDictionary *body = [NSMutableDictionary dictionaryWithDictionary:parameters];
    NSArray *reserved = [NSArray arrayWithObjects:@"id", @"hash", @"token", @"new_sort", nil];
    for (NSString *key in reserved) if ([body objectForKey:key]) {
        *error = PKV1Error(400, @"reserved api parameter"); return nil;
    }
    [body setObject:[NSNumber numberWithInt:1] forKey:@"new_sort"];
    NSMutableArray *values = [NSMutableArray array];
    for (id key in body) {
        if (![key isKindOfClass:[NSString class]]) { *error = PKV1Error(400, @"invalid api parameter name"); return nil; }
        id value = [body objectForKey:key];
        if ([value isKindOfClass:[NSArray class]]) {
            if ([value count] > 128) { *error = PKV1Error(400, @"too many api parameter values"); return nil; }
            for (id element in value) if (!PKV1AddScalar(element, values)) { *error = PKV1Error(400, @"unsupported nested api parameter"); return nil; }
        } else if ([value isKindOfClass:[NSDictionary class]]) {
            if ([value count] > 128) { *error = PKV1Error(400, @"too many api parameter values"); return nil; }
            for (id nestedKey in value) {
                if (![nestedKey isKindOfClass:[NSString class]] || !PKV1AddScalar([value objectForKey:nestedKey], values)) {
                    *error = PKV1Error(400, @"unsupported nested api parameter"); return nil;
                }
            }
        } else if (!PKV1AddScalar(value, values)) { *error = PKV1Error(400, @"unsupported api parameter"); return nil; }
    }
    [values sortUsingFunction:PKV1Compare context:NULL];
    NSString *joined = [values componentsJoinedByString:@","];
    NSString *token = [NSString stringWithFormat:@"%.0f", [[NSDate date] timeIntervalSince1970] * 1000.0];
    char signature[45];
    if (!pk_v1_signature([method UTF8String], [token UTF8String], [joined UTF8String], mbedtls_md5, signature, sizeof(signature))) {
        *error = PKV1Error(400, @"could not sign api request"); return nil;
    }
    [body setObject:@"iws" forKey:@"id"];
    [body setObject:token forKey:@"token"];
    [body setObject:[NSString stringWithUTF8String:signature] forKey:@"hash"];
    return body;
}

static void PKV1Send(NSString *method, NSDictionary *parameters, BOOL allowEmpty, PKV1Completion completion) {
    NSError *error = nil;
    NSDictionary *request = PKV1Build(method, parameters, &error);
    NSData *body = request ? [NSJSONSerialization dataWithJSONObject:request options:0 error:&error] : nil;
    NSString *deviceID = PKV1DeviceID();
    if (!body || body.length > 65536 || !deviceID.length) {
        if (!error) error = PKV1Error(400, @"invalid or oversized api request");
        if (completion) { NSError *result = error; dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, result); }); }
        return;
    }
    PKHTTPPostV1(method, body, deviceID, ^(NSData *data, NSError *transportError) {
        if (transportError) { if (completion) completion(nil, transportError); return; }
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            NSError *replyError = nil;
            id response = nil;
            id envelope = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            if (![envelope isKindOfClass:[NSDictionary class]]) replyError = PKV1Error(422, @"unsupported api response");
            else {
                id failure = [envelope objectForKey:@"error"];
                if (failure && failure != [NSNull null]) {
                    if (![failure isKindOfClass:[NSDictionary class]]) replyError = PKV1Error(422, @"unsupported api error");
                    else {
                        id message = [failure objectForKey:@"message"];
                        id code = [failure objectForKey:@"message_code"];
                        replyError = PKV1Error([code respondsToSelector:@selector(integerValue)] ? [code integerValue] : 1,
                                               [message isKindOfClass:[NSString class]] && [message length] ? message : @"api request failed");
                    }
                } else {
                    response = [envelope objectForKey:@"response"];
                    if (response == [NSNull null]) response = nil;
                    if (!response && !allowEmpty) replyError = PKV1Error(422, @"api response is missing");
                }
            }
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(response, replyError); });
            [pool drain];
        });
    });
}

void PKV1Request(NSString *method, NSDictionary *parameters, PKV1Completion completion) {
    PKV1Send(method, parameters, NO, completion);
}

void PKV1Action(NSString *method, NSDictionary *parameters, void (^completion)(NSError *error)) {
    PKV1Send(method, parameters, YES, ^(id response, NSError *error) {
        (void)response;
        if (completion) completion(error);
    });
}

void PKV1Feed(NSString *feed, NSInteger page, PKV1Completion completion) {
    if (!feed) feed = @"";
    PKV1Request(@"feed", [NSDictionary dictionaryWithObjectsAndKeys:feed, @"cmd", [NSNumber numberWithInteger:page], @"page", nil], completion);
}
void PKV1Search(NSString *query, NSInteger page, PKV1Completion completion) {
    if (!query) query = @"";
    PKV1Request(@"search", [NSDictionary dictionaryWithObjectsAndKeys:query, @"text", [NSNumber numberWithInteger:page], @"page", nil], completion);
}
void PKV1Story(NSNumber *storyID, NSInteger page, PKV1Completion completion) {
    if (!storyID) storyID = [NSNumber numberWithInt:0];
    PKV1Request(@"story.get", [NSDictionary dictionaryWithObjectsAndKeys:storyID, @"story_id", [NSNumber numberWithInteger:page], @"page", nil], completion);
}


static void PKV1Invalid(PKV1Completion completion) {
    if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(nil, PKV1Error(400, @"invalid request parameters")); });
}

static BOOL PKV1PositiveID(NSNumber *value) {
    return [value isKindOfClass:[NSNumber class]] && [value longLongValue] > 0;
}

void PKV1SignIn(NSString *username, NSString *password, PKV1Completion completion) {
    if (![username isKindOfClass:[NSString class]] || !username.length || username.length > 256 ||
        ![password isKindOfClass:[NSString class]] || !password.length || password.length > 4096) {
        PKV1Invalid(completion); return;
    }
    PKV1Request(@"user.auth", [NSDictionary dictionaryWithObjectsAndKeys:username, @"user_name", password, @"password", nil], completion);
}

BOOL PKV1IsUnauthorized(NSError *error) {
    return [error.domain isEqualToString:PKV1ErrorDomain] && error.code == 401;
}

void PKV1Reauthenticate(NSString *password, void (^completion)(NSError *error)) {
    NSString *username = PKSessionUsername();
    if (!username.length) {
        if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(PKV1Error(401, @"no signed in account")); });
        return;
    }
    PKV1SignIn(username, password, ^(id response, NSError *error) {
        (void)response;
        if (completion) completion(error);
    });
}

void PKV1SignOut(PKV1Completion completion) {
    PKV1Request(@"user.logout", [NSDictionary dictionary], completion);
}

void PKV1Profile(NSString *username, NSNumber *currentUserID, PKV1Completion completion) {
    if (![username isKindOfClass:[NSString class]] || !username.length || username.length > 256 ||
        (currentUserID && !PKV1PositiveID(currentUserID))) { PKV1Invalid(completion); return; }
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObject:username forKey:@"user_name"];
    if (currentUserID) [params setObject:currentUserID forKey:@"current_user_id"];
    PKV1Request(@"user.profile.get", params, completion);
}

void PKV1ProfileRating(NSString *username, void (^completion)(NSString *rating, BOOL negative, NSError *error)) {
    PKV1Profile(username, nil, ^(id response, NSError *error) {
        id user = [response isKindOfClass:[NSDictionary class]] ? [response objectForKey:@"user"] : nil;
        id value = [user isKindOfClass:[NSDictionary class]] ? [user objectForKey:@"rating"] : nil;
        NSString *rating = nil;
        int negative = 0;
        if ([value isKindOfClass:[NSString class]]) rating = value;
        else if ([value isKindOfClass:[NSNumber class]] && CFGetTypeID((CFTypeRef)value) != CFBooleanGetTypeID()) rating = [value stringValue];
        const char *bytes = rating.length <= 32 ? [rating UTF8String] : NULL;
        if (!error && (!bytes || !pk_profile_rating(bytes, strlen(bytes), &negative)))
            error = PKV1Error(422, @"profile rating is missing or invalid");
        if (completion) completion(error ? nil : rating, negative ? YES : NO, error);
    });
}

void PKV1CommentChildren(NSNumber *commentID, NSNumber *userID, PKV1Completion completion) {
    if (!PKV1PositiveID(commentID) || (userID && !PKV1PositiveID(userID))) { PKV1Invalid(completion); return; }
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObject:commentID forKey:@"comment_id"];
    if (userID) [params setObject:userID forKey:@"user_id"];
    PKV1Request(@"comments.children.get", params, completion);
}

void PKV1CreateComment(NSNumber *storyID, NSNumber *userID, NSNumber *parentID,
                       NSString *text, BOOL plainText, NSArray *images, PKV1Completion completion) {
    if (!PKV1PositiveID(storyID) || !PKV1PositiveID(userID) || (parentID && !PKV1PositiveID(parentID)) ||
        ![text isKindOfClass:[NSString class]] || text.length > 16000 ||
        (images && (![images isKindOfClass:[NSArray class]] || images.count > 32)) || (!text.length && !images.count)) {
        PKV1Invalid(completion); return;
    }
    for (id image in images) if (![image isKindOfClass:[NSString class]] || ![image length] || [image length] > 4096) {
        PKV1Invalid(completion); return;
    }
    NSMutableDictionary *params = [NSMutableDictionary dictionaryWithObjectsAndKeys:storyID, @"story_id", userID, @"user_id", text, @"desc", nil];
    if (parentID) [params setObject:parentID forKey:@"parent_id"];
    if (images.count) [params setObject:images forKey:@"images"];
    if (text.length) [params setObject:[NSNumber numberWithBool:plainText] forKey:@"plain_text"];
    PKV1Request(@"comment.create", params, completion);
}

void PKV1Vote(NSString *type, NSNumber *itemID, NSNumber *userID, NSInteger vote, PKV1Completion completion) {
    if (!([type isEqualToString:@"story"] || [type isEqualToString:@"comment"]) ||
        !PKV1PositiveID(itemID) || !PKV1PositiveID(userID) || vote < -1 || vote > 1) {
        PKV1Invalid(completion); return;
    }
    NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:type, @"type", itemID, @"item_id", userID, @"user_id", [NSNumber numberWithInteger:vote], @"vote", nil];
    PKV1Request(@"vote.new", params, completion);
}
