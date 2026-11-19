#import "pk_auth.h"
#import "pk_v1.h"
#import "pk_lang.h"
#import "pk_http.h"
#import "pk_model.h"
#include <mbedtls/md5.h>
#include <stdio.h>

static NSString * const PKAuthStateKey = @"pk_auth_state";
static NSString * const PKUsernameKey = @"pk_auth_username";
static NSString * const PKAuthErrorDomain = @"PikabuAuth";

static const NSUInteger PKAuthMaximumReplyBytes = 64 * 1024;
static const NSUInteger PKAuthMaximumNonceLength = 128;
static const NSUInteger PKAuthMaximumMessageLength = 240;

enum {
    PKAuthErrorMissingInput = 400,
    PKAuthErrorRefused = 401,
    PKAuthErrorUnexpectedReply = 422,
    PKAuthErrorHash = 423,
    PKAuthErrorNoLogoutToken = 424
};

static NSError *PKAuthError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:PKAuthErrorDomain code:code
                           userInfo:[NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey]];
}

static BOOL PKCookieDomainIsPikabu(NSString *domain) {
    NSString *lower = [domain lowercaseString];
    return [lower isEqualToString:@"pikabu.ru"] || [lower hasSuffix:@".pikabu.ru"];
}

static NSString *PKCaptureAuthValue(NSString *html, NSString *key) {
    NSString *pattern = [NSString stringWithFormat:@"\\\"%@\\\"\\s*:\\s*\\\"?([^\\\",}]+)", key];
    NSRegularExpression *expression = [NSRegularExpression regularExpressionWithPattern:pattern options:0 error:nil];
    NSTextCheckingResult *match = [expression firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
    return match.numberOfRanges > 1 ? [html substringWithRange:[match rangeAtIndex:1]] : nil;
}

/* "data" is an empty array on a refusal. anything else, like the ddos-guard html challenge, is not an answer */
static NSDictionary *PKAuthEnvelope(NSData *body) {
    if (!body.length || body.length > PKAuthMaximumReplyBytes) return nil;
    id json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
    if (![json isKindOfClass:[NSDictionary class]]) return nil;
    if (![[json objectForKey:@"result"] isKindOfClass:[NSNumber class]]) return nil;
    return json;
}

static NSError *PKAuthUnexpectedReply(void) {
    return PKAuthError(PKAuthErrorUnexpectedReply,
                       PKText(@"Weeabu ответил не так, как ожидалось. Если сайт просит проверку от ботов, пройдите её в Safari и повторите."));
}

static NSError *PKAuthRefusal(NSDictionary *envelope, NSString *fallback) {
    id message = [envelope objectForKey:@"message"];
    if ([message isKindOfClass:[NSString class]] && [message length]) {
        if ([message length] > PKAuthMaximumMessageLength) message = [message substringToIndex:PKAuthMaximumMessageLength];
        return PKAuthError(PKAuthErrorRefused, message);
    }
    return PKAuthError(PKAuthErrorRefused, fallback);
}

static NSString *PKMD5(NSString *value) {
    unsigned char digest[16];
    char hex[33];
    size_t i;
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (!data || mbedtls_md5(data.bytes, data.length, digest) != 0) return nil;
    for (i = 0; i < sizeof(digest); i++) snprintf(hex + i * 2, 3, "%02x", digest[i]);
    hex[32] = 0;
    return [NSString stringWithUTF8String:hex];
}

static void PKClearSession(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:PKAuthStateKey];
    [defaults removeObjectForKey:PKUsernameKey];
    [defaults removeObjectForKey:@"pk_user_id"];
    [defaults synchronize];
}

/* the home page carries "userID":0 for a guest */
static void PKFinishAuth(NSData *data, NSError *error, NSString *fallbackUsername,
                         PKAuthCompletion completion) {
    NSString *html = PKHTTPText(data);
    NSInteger userID = [[PKCaptureAuthValue(html, @"userID") stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\""]] integerValue];
    BOOL authenticated = !error && userID > 0;
    NSString *name = PKCaptureAuthValue(html, @"userName");
    if (!name.length) name = fallbackUsername;
    if (authenticated) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        [defaults setBool:YES forKey:PKAuthStateKey];
        if (name.length) [defaults setObject:name forKey:PKUsernameKey];
        [defaults setInteger:userID forKey:@"pk_user_id"];
        [defaults synchronize];
    } else if (!error) {
        PKClearSession();
        error = PKAuthError(PKAuthErrorRefused, PKText(@"Не удалось войти. Проверьте логин и пароль."));
    }
    if (completion) completion(authenticated, name, error);
}

void PKSignIn(NSString *username, NSString *password, PKAuthCompletion completion) {
    if (!username.length || !password.length) {
        if (completion) completion(NO, nil, PKAuthError(PKAuthErrorMissingInput, PKText(@"Введите логин и пароль.")));
        return;
    }
    PKHTTPGet(@"https://pikabu.ru/ajax/get_nonce.php", ^(NSData *nonceData, NSError *nonceError) {
        if (nonceError) { if (completion) completion(NO, nil, nonceError); return; }
        NSDictionary *nonceReply = PKAuthEnvelope(nonceData);
        if (!nonceReply) { if (completion) completion(NO, nil, PKAuthUnexpectedReply()); return; }
        if (![[nonceReply objectForKey:@"result"] boolValue]) {
            if (completion) completion(NO, nil, PKAuthRefusal(nonceReply, PKText(@"Не удалось получить ключ авторизации.")));
            return;
        }
        NSDictionary *nonceBody = [nonceReply objectForKey:@"data"];
        id nonceValue = [nonceBody isKindOfClass:[NSDictionary class]] ? [nonceBody objectForKey:@"nonce"] : nil;
        if (![nonceValue isKindOfClass:[NSString class]] || ![nonceValue length] ||
            [nonceValue length] > PKAuthMaximumNonceLength) {
            if (completion) completion(NO, nil, PKAuthError(PKAuthErrorUnexpectedReply, PKText(@"Не удалось получить ключ авторизации.")));
            return;
        }
        NSString *nonce = nonceValue;
        NSString *cnonce = [NSString stringWithFormat:@"%.16f", (double)arc4random() / 4294967296.0];
        NSString *hash = PKMD5([NSString stringWithFormat:@"%@%@%@", nonce, cnonce, password]);
        if (!hash.length) {
            if (completion) completion(NO, nil, PKAuthError(PKAuthErrorHash, PKText(@"Не удалось подготовить вход.")));
            return;
        }
        NSDictionary *fields = [NSDictionary dictionaryWithObjectsAndKeys:@"login", @"mode", username, @"username", password, @"password", cnonce, @"cnonce", hash, @"hash", nil];
        PKHTTPPost(@"https://pikabu.ru/ajax/auth.php", fields, nil, ^(NSData *data, NSError *error) {
            if (error) { if (completion) completion(NO, nil, error); return; }
            NSDictionary *reply = PKAuthEnvelope(data);
            if (!reply) { if (completion) completion(NO, nil, PKAuthUnexpectedReply()); return; }
            if (![[reply objectForKey:@"result"] boolValue]) {
                if (completion) completion(NO, nil, PKAuthRefusal(reply, PKText(@"Не удалось войти. Проверьте логин и пароль.")));
                return;
            }
/* result true is the site's word, the home page says whose session it is */
            PKHTTPGet(@"https://pikabu.ru/", ^(NSData *home, NSError *homeError) {
                PKFinishAuth(home, homeError, username, ^(BOOL authenticated, NSString *name, NSError *finishError) {
                    if (!authenticated) { if (completion) completion(authenticated, name, finishError); return; }
                    /* without the api session, settings and every call that names the user answer Unauthorized */
                    PKV1SignIn(username, password, ^(id response, NSError *apiError) {
                        (void)response;
                        if (apiError) NSLog(@"weeabu: api session was not opened: %@", apiError);
                        if (completion) completion(authenticated, name, finishError);
                    });
                });
            });
        });
    });
}

void PKCheckSession(PKAuthCompletion completion) {
    PKHTTPGet(@"https://pikabu.ru/", ^(NSData *data, NSError *error) {
        PKFinishAuth(data, error, PKSessionUsername(), completion);
    });
}

static void PKClearLocalSession(void) {
    NSHTTPCookieStorage *storage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    for (NSHTTPCookie *cookie in [[storage.cookies copy] autorelease]) {
        if (PKCookieDomainIsPikabu(cookie.domain)) [storage deleteCookie:cookie];
    }
    PKClearSession();
}

void PKSignOut(PKSignOutCompletion completion) {
/* logout.php wants the csrf token of the page, and deleting cookies leaves the session valid on the server */
    PKHTTPGet(@"https://pikabu.ru/", ^(NSData *page, NSError *pageError) {
        NSString *token = pageError ? nil : PKCSRFTokenFromHTML(PKHTTPText(page));
        if (!token.length) {
            NSError *error = pageError ?: PKAuthError(PKAuthErrorNoLogoutToken, PKText(@"Не удалось получить токен выхода."));
            PKClearLocalSession();
            if (completion) completion(error);
            return;
        }
        PKHTTPPost(@"https://pikabu.ru/ajax/logout.php", [NSDictionary dictionary], token, ^(NSData *data, NSError *error) {
            if (!error) {
                NSDictionary *reply = PKAuthEnvelope(data);
                if (!reply) error = PKAuthUnexpectedReply();
                else if (![[reply objectForKey:@"result"] boolValue])
                    error = PKAuthRefusal(reply, PKText(@"Сайт не подтвердил выход."));
            }
            PKClearLocalSession();
            if (completion) completion(error);
        });
    });
}

BOOL PKSessionWasAuthenticated(void) { return [[NSUserDefaults standardUserDefaults] boolForKey:PKAuthStateKey]; }
NSNumber *PKSessionUserID(void) {
    NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:@"pk_user_id"];
    return value > 0 ? [NSNumber numberWithInteger:value] : nil;
}
NSString *PKSessionUsername(void) { return [[NSUserDefaults standardUserDefaults] stringForKey:PKUsernameKey]; }
