#import "pk_http.h"
#import "pk_tls_image.h"

static NSString * const PKHTTPErrorDomain = @"PikabuHTTP";

/* the cookie and, on signin.php, the password ride along, so a redirect may not leave the issuing authority */
static NSString * const PKHTTPAuthority = @"pikabu.ru";

static const NSUInteger PKHTTPMaximumBodyBytes = 8 * 1024 * 1024;
static const NSUInteger PKHTTPMaximumRedirects = 4;
static const NSTimeInterval PKHTTPTimeout = 25.0;

enum {
    PKHTTPErrorInvalidURL = -1,
    PKHTTPErrorNoResponse = -2,
    PKHTTPErrorBodyTooLarge = -3,
    PKHTTPErrorRedirectOffAuthority = -4,
    PKHTTPErrorTooManyRedirects = -5
};

static NSError *PKHTTPError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:PKHTTPErrorDomain code:code
                           userInfo:[NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey]];
}

NSString *PKHTTPPercentEncode(NSString *value) {
    NSData *data = [value dataUsingEncoding:NSUTF8StringEncoding];
    const unsigned char *bytes = data.bytes;
    NSMutableString *result = [NSMutableString stringWithCapacity:data.length];
    NSUInteger index;
    for (index = 0; index < data.length; index++) {
        unsigned char c = bytes[index];
        if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') ||
            c == '-' || c == '_' || c == '.' || c == '~')
            [result appendFormat:@"%c", c];
        else
            [result appendFormat:@"%%%02X", c];
    }
    return result;
}

NSString *PKHTTPText(NSData *data) {
    if (!data.length) return nil;
    NSString *text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
/* cp1251 accepts almost any bytes, so trying it first turns every utf-8 page into mojibake */
    if (!text) text = [[[NSString alloc] initWithData:data encoding:NSWindowsCP1251StringEncoding] autorelease];
    return text;
}

static BOOL PKHTTPHostInAuthority(NSString *host) {
    NSString *lower = [host lowercaseString];
    return [lower isEqualToString:PKHTTPAuthority] ||
           [lower hasSuffix:[@"." stringByAppendingString:PKHTTPAuthority]];
}

/* sendAsynchronousRequest: has no redirect hook and buffers the whole body, so neither the authority rule
   nor the byte cap could hold */
@interface PKHTTPTask : NSObject <NSURLConnectionDataDelegate> {
    NSURLConnection *_connection;
    NSMutableData *_body;
    PKHTTPCompletion _completion;
    NSUInteger _redirects;
    NSInteger _status;
    BOOL _finished;
    NSString *_initialHost;
}
- (id)initWithRequest:(NSURLRequest *)request completion:(PKHTTPCompletion)completion;
- (void)start;
@end

@implementation PKHTTPTask

+ (NSOperationQueue *)deliveryQueue {
    static NSOperationQueue *queue;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = 4;
    });
    return queue;
}

- (id)initWithRequest:(NSURLRequest *)request completion:(PKHTTPCompletion)completion {
    if ((self = [super init])) {
        _completion = [completion copy];
        _initialHost = [[[request URL] host] lowercaseString].copy;
        _body = [[NSMutableData alloc] init];
        _connection = [[NSURLConnection alloc] initWithRequest:request delegate:self startImmediately:NO];
        [_connection setDelegateQueue:[PKHTTPTask deliveryQueue]];
    }
    return self;
}

- (void)start {
    if (!_connection) {
        [self finishWithError:PKHTTPError(PKHTTPErrorInvalidURL, @"request could not be created")];
        return;
    }
/* the delegate callbacks retain nothing, so the task holds itself until a terminal path releases it */
    [self retain];
    [_connection start];
}

- (void)finishWithError:(NSError *)error {
    if (_finished) return;
    _finished = YES;
    NSData *data = error ? nil : [[_body copy] autorelease];
/* copying the block retains the completion, body and error, so the task may go away after handing them over */
    if (_completion) {
        PKHTTPCompletion completion = _completion;
        dispatch_async(dispatch_get_main_queue(), ^{ completion(data, error); });
    }
    [_connection cancel];
    [self release];
}

- (NSURLRequest *)connection:(NSURLConnection *)connection
             willSendRequest:(NSURLRequest *)request
            redirectResponse:(NSURLResponse *)response {
    (void)connection;
    if (!response) return request;
    if (++_redirects > PKHTTPMaximumRedirects) {
        [self finishWithError:PKHTTPError(PKHTTPErrorTooManyRedirects, @"too many redirects")];
        return nil;
    }
    NSURL *url = [request URL];
    if (![[[url scheme] lowercaseString] isEqualToString:@"https"] || !PKHTTPHostInAuthority([url host]) ||
        ([_initialHost isEqualToString:@"api.pikabu.ru"] &&
         (![[[url host] lowercaseString] isEqualToString:_initialHost] ||
          ([url port] && [[url port] integerValue] != 443)))) {
        [self finishWithError:PKHTTPError(PKHTTPErrorRedirectOffAuthority,
                                          @"redirect leaves pikabu.ru and would carry the session")];
        return nil;
    }
    return request;
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
    (void)connection;
    _status = [response isKindOfClass:[NSHTTPURLResponse class]] ? [(NSHTTPURLResponse *)response statusCode] : 0;
    long long expected = [response expectedContentLength];
    if (expected != NSURLResponseUnknownLength && expected > (long long)PKHTTPMaximumBodyBytes) {
        [self finishWithError:PKHTTPError(PKHTTPErrorBodyTooLarge, @"server response is too large")];
        return;
    }
    [_body setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    (void)connection;
/* checking the finished length would already have paid for the allocation this cap prevents */
    if (data.length > PKHTTPMaximumBodyBytes || _body.length > PKHTTPMaximumBodyBytes - data.length) {
        [self finishWithError:PKHTTPError(PKHTTPErrorBodyTooLarge, @"server response is too large")];
        return;
    }
    [_body appendData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    (void)connection;
    [self finishWithError:error];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
    (void)connection;
    if (!_status)
        [self finishWithError:PKHTTPError(PKHTTPErrorNoResponse, @"server returned no response")];
    else if (_status >= 400)
        [self finishWithError:[NSError errorWithDomain:PKHTTPErrorDomain code:_status
                                              userInfo:[NSDictionary dictionaryWithObject:@"server returned an error"
                                                                                   forKey:NSLocalizedDescriptionKey]]];
    else
        [self finishWithError:nil];
}

- (void)dealloc {
    [_connection release];
    [_initialHost release];
    [_body release];
    [_completion release];
    [super dealloc];
}
@end

static NSMutableURLRequest *PKRequest(NSString *urlString) {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url || ![[[url scheme] lowercaseString] isEqualToString:@"https"] || !PKHTTPHostInAuthority([url host]))
        return nil;
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                          cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                                                      timeoutInterval:PKHTTPTimeout];
    [request setValue:@"Mozilla/5.0 (iPhone; CPU iPhone OS 6_0 like Mac OS X) PikabuLegacy/1.0" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"text/html,application/xhtml+xml,application/json" forHTTPHeaderField:@"Accept"];
    return request;
}

static void PKHTTPRun(NSMutableURLRequest *request, PKHTTPCompletion completion) {
    PKHTTPTask *task = [[[PKHTTPTask alloc] initWithRequest:request completion:completion] autorelease];
    [task start];
}

static void PKHTTPFailInvalidURL(PKHTTPCompletion completion) {
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(nil, PKHTTPError(PKHTTPErrorInvalidURL, @"url is not an https pikabu.ru address"));
    });
}

void PKHTTPGet(NSString *urlString, PKHTTPCompletion completion) {
    NSMutableURLRequest *request = PKRequest(urlString);
    if (!request) {
        PKHTTPFailInvalidURL(completion);
        return;
    }
    [request setHTTPMethod:@"GET"];
    PKHTTPRun(request, completion);
}

void PKHTTPPost(NSString *urlString, NSDictionary *fields, NSString *csrfToken, PKHTTPCompletion completion) {
    NSMutableURLRequest *request = PKRequest(urlString);
    if (!request) {
        PKHTTPFailInvalidURL(completion);
        return;
    }
    NSMutableArray *parts = [NSMutableArray arrayWithCapacity:fields.count];
    for (NSString *key in fields) {
        NSString *value = [[fields objectForKey:key] description];
        [parts addObject:[NSString stringWithFormat:@"%@=%@", PKHTTPPercentEncode(key), PKHTTPPercentEncode(value)]];
    }
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/x-www-form-urlencoded; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
    NSInteger offset = -[[NSTimeZone localTimeZone] secondsFromGMT] / 60;
    [request setValue:[NSString stringWithFormat:@"%ld", (long)offset] forHTTPHeaderField:@"X-Timezone-Offset"];
    if (csrfToken.length) [request setValue:csrfToken forHTTPHeaderField:@"X-Csrf-Token"];
    [request setHTTPBody:[[parts componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding]];
    PKHTTPRun(request, completion);
}

void PKHTTPPostV1(NSString *method, NSData *body, NSString *deviceID, PKHTTPCompletion completion) {
    NSCharacterSet *invalid = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789._"] invertedSet];
    if (!method.length || method.length > 128 || [method rangeOfCharacterFromSet:invalid].location != NSNotFound || !body.length || body.length > 65536 || !deviceID.length) {
        PKHTTPFailInvalidURL(completion);
        return;
    }
    NSString *url = [@"https://api.pikabu.ru/v1/" stringByAppendingString:method];
    NSMutableURLRequest *request = PKRequest(url);
    if (!request) { PKHTTPFailInvalidURL(completion); return; }
    [request setHTTPMethod:@"POST"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    [request setValue:@"ru.pikabu.android/1.17.0 (Pixel 4; Android 10)" forHTTPHeaderField:@"User-Agent"];
    [request setValue:deviceID forHTTPHeaderField:@"DeviceId"];
    [request setHTTPBody:body];
    BOOL publicMethod = [method isEqualToString:@"story.get"] || [method isEqualToString:@"user.profile.get"];
    PKHTTPRun(request, ^(NSData *data, NSError *error) {
        BOOL trustFailure = [error.domain isEqualToString:NSURLErrorDomain] &&
            (error.code == NSURLErrorSecureConnectionFailed || error.code == NSURLErrorServerCertificateUntrusted ||
             error.code == NSURLErrorServerCertificateHasUnknownRoot);
        if (!publicMethod || !trustFailure) { if (completion) completion(data, error); return; }
        /* ios 5 and 6 lack the current api root, mbedtls still checks the full chain and hostname */
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            NSError *fallbackError = nil;
            NSData *result = PKTLSV1Post(method, body, deviceID, &fallbackError);
            if (completion) dispatch_async(dispatch_get_main_queue(), ^{ completion(result, fallbackError); });
            [pool drain];
        });
    });
}
