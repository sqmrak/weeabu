#import "pk_tls_image.h"
#import "pk_tls_rules.h"

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netdb.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <unistd.h>

#include "mbedtls/ctr_drbg.h"
#include "mbedtls/entropy.h"
#include "mbedtls/ssl.h"
#include "mbedtls/x509_crt.h"

#ifndef MBEDTLS_ERR_NET_RECV_FAILED
#define MBEDTLS_ERR_NET_RECV_FAILED -0x004C
#endif
#ifndef MBEDTLS_ERR_NET_SEND_FAILED
#define MBEDTLS_ERR_NET_SEND_FAILED -0x004E
#endif

#define PKTLS_MAX_IMAGE_BYTES (24 * 1024 * 1024)
#define PKTLS_MAX_VIDEO_BYTES (256 * 1024 * 1024)
#define PKTLS_MAX_JSON_BYTES (8 * 1024 * 1024)
#define PKTLS_TIMEOUT_SECONDS 20
#define PKTLS_MAX_REDIRECTS 3

/* a video is written to its file as it arrives: holding one whole is a jetsam kill on a 256 MB device */
typedef struct {
    int fd;
    NSMutableData *buffer;
    size_t written;
    size_t limit;
} PKTLSSink;

static NSError *PKTLSError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"PikabuTLSImage" code:code
                            userInfo:[NSDictionary dictionaryWithObject:message ?: @"secure request failed"
                                                                 forKey:NSLocalizedDescriptionKey]];
}

static BOOL PKTLSSinkWrite(PKTLSSink *sink, const unsigned char *bytes, size_t length) {
    if (!length) return YES;
    if (sink->written > sink->limit || length > sink->limit - sink->written) return NO;
    if (sink->fd >= 0) {
        size_t offset = 0;
        while (offset < length) {
            ssize_t result = write(sink->fd, bytes + offset, length - offset);
            if (result > 0) { offset += (size_t)result; continue; }
            if (result < 0 && errno == EINTR) continue;
            return NO;
        }
    } else {
        [sink->buffer appendBytes:bytes length:length];
    }
    sink->written += length;
    return YES;
}

/* a redirect is followed only before the first content byte reached the sink */
static BOOL PKTLSSinkReset(PKTLSSink *sink) {
    sink->written = 0;
    if (sink->fd < 0) {
        [sink->buffer setLength:0];
        return YES;
    }
    return lseek(sink->fd, 0, SEEK_SET) == 0 && ftruncate(sink->fd, 0) == 0;
}

static int PKTLSWaitForSocket(int fd, int write_side) {
    fd_set fds;
    struct timeval timeout = { PKTLS_TIMEOUT_SECONDS, 0 };
    FD_ZERO(&fds);
    FD_SET(fd, &fds);
    return select(fd + 1, write_side ? NULL : &fds, write_side ? &fds : NULL, NULL, &timeout) > 0;
}

static int PKTLSConnect(const char *host) {
    struct addrinfo hints;
    struct addrinfo *addresses = NULL;
    struct addrinfo *address;
    int fd = -1;
    memset(&hints, 0, sizeof(hints));
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_family = AF_UNSPEC;
    if (getaddrinfo(host, "443", &hints, &addresses) != 0) return -1;
    for (address = addresses; address; address = address->ai_next) {
        int flags;
        int connect_error = 0;
        socklen_t error_length = sizeof(connect_error);
        fd = socket(address->ai_family, address->ai_socktype, address->ai_protocol);
        if (fd < 0) continue;
        flags = fcntl(fd, F_GETFL, 0);
        if (flags < 0 || fcntl(fd, F_SETFL, flags | O_NONBLOCK) < 0) { close(fd); fd = -1; continue; }
        if (connect(fd, address->ai_addr, address->ai_addrlen) < 0 &&
            (errno != EINPROGRESS || !PKTLSWaitForSocket(fd, 1) ||
             getsockopt(fd, SOL_SOCKET, SO_ERROR, &connect_error, &error_length) < 0 || connect_error != 0)) {
            close(fd); fd = -1; continue;
        }
        if (fcntl(fd, F_SETFL, flags) < 0) { close(fd); fd = -1; continue; }
        {
            struct timeval timeout = { PKTLS_TIMEOUT_SECONDS, 0 };
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, sizeof(timeout));
        }
        break;
    }
    freeaddrinfo(addresses);
    return fd;
}

static int PKTLSSend(void *context, const unsigned char *buffer, size_t length) {
    int fd = *(int *)context;
    ssize_t result = send(fd, buffer, length, 0);
    if (result >= 0) return (int)result;
    return (errno == EAGAIN || errno == EWOULDBLOCK) ? MBEDTLS_ERR_SSL_WANT_WRITE : MBEDTLS_ERR_NET_SEND_FAILED;
}

static int PKTLSReceive(void *context, unsigned char *buffer, size_t length) {
    int fd = *(int *)context;
    ssize_t result = recv(fd, buffer, length, 0);
    if (result > 0) return (int)result;
    if (result == 0) return MBEDTLS_ERR_SSL_CONN_EOF;
    return (errno == EAGAIN || errno == EWOULDBLOCK) ? MBEDTLS_ERR_SSL_WANT_READ : MBEDTLS_ERR_NET_RECV_FAILED;
}

static BOOL PKTLSURLAllowed(NSURL *url) {
    NSString *host = [[url host] lowercaseString];
    NSNumber *port = [url port];
    return url && [[[url scheme] lowercaseString] isEqualToString:@"https"] && host.length &&
        !url.user.length && !url.password.length && (!port || [port integerValue] == 443) &&
        PKTLSHostAllowed([host UTF8String]);
}

static NSData *PKTLSCAData(void) {
    return [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"pikabu-ca" ofType:@"pem"]];
}

static NSString *PKTLSHeaderValue(const unsigned char *data, size_t length, NSString *name) {
    NSString *text = [[[NSString alloc] initWithBytes:data length:length encoding:NSISOLatin1StringEncoding] autorelease];
    NSString *prefix = [name stringByAppendingString:@":"];
    for (NSString *line in [text componentsSeparatedByString:@"\r\n"]) {
        if ([[line substringToIndex:MIN(line.length, prefix.length)] caseInsensitiveCompare:prefix] == NSOrderedSame)
            return [[line substringFromIndex:prefix.length] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    }
    return nil;
}

typedef enum { PKTLSImage, PKTLSVideo, PKTLSV1 } PKTLSKind;
static BOOL PKTLSFetch(NSURL *url, PKTLSSink *sink, NSError **error, NSUInteger redirects, PKTLSKind kind, NSData *postBody, NSString *deviceID);

/* peels off the transfer encoding when the response used one */
static BOOL PKTLSDeliver(PKTLSSink *sink, PKTLSChunked *chunked, BOOL is_chunked, BOOL *finished,
                         const unsigned char *bytes, size_t length) {
    if (!is_chunked) return PKTLSSinkWrite(sink, bytes, length);
    while (length && !*finished) {
        unsigned char decoded[16384];
        size_t consumed = 0;
        size_t produced = 0;
        int result = PKTLSChunkedFeed(chunked, bytes, length, &consumed, decoded, sizeof(decoded), &produced);
        if (result == PKTLS_CHUNK_ERROR) return NO;
        if (produced && !PKTLSSinkWrite(sink, decoded, produced)) return NO;
        if (result == PKTLS_CHUNK_DONE) { *finished = YES; return YES; }
        if (!consumed && !produced) return NO;
        bytes += consumed;
        length -= consumed;
    }
    return YES;
}

static BOOL PKTLSFetch(NSURL *url, PKTLSSink *sink, NSError **error, NSUInteger redirects, PKTLSKind kind, NSData *postBody, NSString *deviceID) {
    mbedtls_ssl_context ssl;
    mbedtls_ssl_config config;
    mbedtls_ctr_drbg_context drbg;
    mbedtls_entropy_context entropy;
    mbedtls_x509_crt ca;
    NSData *ca_data = nil;
    NSMutableData *head = nil;
    NSString *failure = nil;
    NSString *media_name = kind == PKTLSV1 ? @"api" : (kind == PKTLSVideo ? @"video" : @"image");
    NSString *host;
    NSString *path;
    PKTLSHTTPHeaders headers;
    PKTLSChunked chunked;
    BOOL parsed_headers = NO;
    BOOL body_finished = NO;
    BOOL is_chunked = NO;
    BOOL succeeded = NO;
    int fd = -1;
    int ret;

    memset(&headers, 0, sizeof(headers));
    PKTLSChunkedInit(&chunked, sink->limit);

    if (redirects > PKTLS_MAX_REDIRECTS || !PKTLSURLAllowed(url)) {
        if (error) *error = PKTLSError(-1000, [NSString stringWithFormat:@"disallowed secure %@ URL", media_name]);
        return NO;
    }
    host = [[url host] lowercaseString];
    path = url.path.length ? url.path : @"/";
    if (url.query.length) path = [path stringByAppendingFormat:@"?%@", url.query];
    if ([path rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]].location != NSNotFound) {
        if (error) *error = PKTLSError(-1000, [NSString stringWithFormat:@"invalid %@ path", media_name]);
        return NO;
    }

    mbedtls_ssl_init(&ssl); mbedtls_ssl_config_init(&config); mbedtls_ctr_drbg_init(&drbg);
    mbedtls_entropy_init(&entropy); mbedtls_x509_crt_init(&ca);

    ca_data = PKTLSCAData();
    {
        NSMutableData *ca_pem = [NSMutableData dataWithData:ca_data];
        unsigned char terminator = 0;
        [ca_pem appendBytes:&terminator length:1];
        if (!ca_data.length || mbedtls_x509_crt_parse(&ca, ca_pem.bytes, ca_pem.length) != 0) {
            failure = @"bundled CA bundle is invalid";
            goto cleanup;
        }
    }
    fd = PKTLSConnect([host UTF8String]);
    if (fd < 0) { failure = @"connect timed out or failed"; goto cleanup; }
    if ((ret = mbedtls_ctr_drbg_seed(&drbg, mbedtls_entropy_func, &entropy, (const unsigned char *)"pikabu-image", 12)) != 0 ||
        (ret = mbedtls_ssl_config_defaults(&config, MBEDTLS_SSL_IS_CLIENT, MBEDTLS_SSL_TRANSPORT_STREAM, MBEDTLS_SSL_PRESET_DEFAULT)) != 0) {
        failure = @"TLS setup failed";
        goto cleanup;
    }
    mbedtls_ssl_conf_authmode(&config, MBEDTLS_SSL_VERIFY_REQUIRED);
    mbedtls_ssl_conf_ca_chain(&config, &ca, NULL);
    mbedtls_ssl_conf_rng(&config, mbedtls_ctr_drbg_random, &drbg);
    mbedtls_ssl_conf_min_tls_version(&config, MBEDTLS_SSL_VERSION_TLS1_2);
    if ((ret = mbedtls_ssl_setup(&ssl, &config)) != 0 || (ret = mbedtls_ssl_set_hostname(&ssl, [host UTF8String])) != 0) {
        failure = @"TLS hostname setup failed";
        goto cleanup;
    }
    mbedtls_ssl_set_bio(&ssl, &fd, PKTLSSend, PKTLSReceive, NULL);
    while ((ret = mbedtls_ssl_handshake(&ssl)) != 0)
        if (ret != MBEDTLS_ERR_SSL_WANT_READ && ret != MBEDTLS_ERR_SSL_WANT_WRITE) {
            failure = @"TLS certificate or handshake failed";
            goto cleanup;
        }
    if (mbedtls_ssl_get_verify_result(&ssl) != 0) { failure = @"TLS certificate verification failed"; goto cleanup; }

    {
        NSString *accept = kind == PKTLSV1 ? @"application/json" : (kind == PKTLSVideo ? @"video/mp4" : @"image/jpeg,image/png,image/gif,image/webp");
        NSString *request;
        if (kind == PKTLSV1) {
            request = [NSString stringWithFormat:
                @"POST %@ HTTP/1.1\r\nHost: %@\r\nAccept: %@\r\nAccept-Encoding: identity\r\nContent-Type: application/json\r\nUser-Agent: ru.pikabu.android/1.17.0 (Pixel 4; Android 10)\r\nDeviceId: %@\r\nContent-Length: %lu\r\nConnection: close\r\n\r\n",
                path, host, accept, deviceID, (unsigned long)postBody.length];
        } else {
            request = [NSString stringWithFormat:
                @"GET %@ HTTP/1.1\r\nHost: %@\r\nAccept: %@\r\nAccept-Encoding: identity\r\nConnection: close\r\n\r\n",
                path, host, accept];
        }
        NSMutableData *request_data = [NSMutableData dataWithData:[request dataUsingEncoding:NSUTF8StringEncoding]];
        if (kind == PKTLSV1) [request_data appendData:postBody];
        size_t sent = 0;
        while (sent < request_data.length) {
            ret = mbedtls_ssl_write(&ssl, (const unsigned char *)request_data.bytes + sent, request_data.length - sent);
            if (ret > 0) { sent += (size_t)ret; continue; }
            if (ret != MBEDTLS_ERR_SSL_WANT_READ && ret != MBEDTLS_ERR_SSL_WANT_WRITE) {
                failure = [NSString stringWithFormat:@"secure %@ request failed", media_name];
                goto cleanup;
            }
        }
    }

    head = [NSMutableData data];
    for (;;) {
        unsigned char buffer[16384];
        ret = mbedtls_ssl_read(&ssl, buffer, sizeof(buffer));
        if (ret == 0 || ret == MBEDTLS_ERR_SSL_CONN_EOF || ret == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY) break;
        if (ret < 0) {
            if (ret == MBEDTLS_ERR_SSL_WANT_READ || ret == MBEDTLS_ERR_SSL_WANT_WRITE) continue;
            failure = [NSString stringWithFormat:@"secure %@ response failed", media_name];
            goto cleanup;
        }
        if (body_finished) continue;

        if (!parsed_headers) {
            /* the head is the only part held whole, capped far below what a body reaches */
            if (head.length > PKTLS_MAX_HEADER_BYTES - (NSUInteger)ret) {
                failure = [NSString stringWithFormat:@"%@ response headers are too large", media_name];
                goto cleanup;
            }
            [head appendBytes:buffer length:(NSUInteger)ret];
            if (!PKTLSParseHTTPHeaders(head.bytes, head.length, &headers)) continue;
            if (headers.header_length > head.length) continue;
            parsed_headers = YES;

            if (headers.status >= 300 && headers.status < 400) {
                if (kind == PKTLSV1) { failure = @"api redirect is not allowed"; goto cleanup; }
                NSString *location = PKTLSHeaderValue(head.bytes, headers.header_length, @"Location");
                NSURL *redirect = location.length ? [NSURL URLWithString:location relativeToURL:url] : nil;
                if (!redirect || !PKTLSURLAllowed(redirect)) {
                    failure = [NSString stringWithFormat:@"%@ redirect has a disallowed URL", media_name];
                    goto cleanup;
                }
                if (!PKTLSSinkReset(sink)) { failure = @"could not restart the download"; goto cleanup; }
                if (fd >= 0) { close(fd); fd = -1; }
                mbedtls_ssl_free(&ssl); mbedtls_ssl_config_free(&config); mbedtls_ctr_drbg_free(&drbg);
                mbedtls_entropy_free(&entropy); mbedtls_x509_crt_free(&ca);
                return PKTLSFetch(redirect, sink, error, redirects + 1, kind, nil, nil);
            }
            if (headers.status < 200 || headers.status >= 300) {
                failure = [NSString stringWithFormat:@"%@ server returned HTTP %d", media_name, headers.status];
                goto cleanup;
            }
            if (kind == PKTLSV1 ? !headers.json_content_type : (kind == PKTLSVideo ? !headers.video_content_type : !headers.image_content_type)) {
                failure = [NSString stringWithFormat:@"%@ response has an unexpected content type", media_name];
                goto cleanup;
            }
            is_chunked = headers.chunked ? YES : NO;
            {
                const unsigned char *body = (const unsigned char *)head.bytes + headers.header_length;
                size_t body_length = head.length - headers.header_length;
                if (!PKTLSDeliver(sink, &chunked, is_chunked, &body_finished, body, body_length)) {
                    failure = [NSString stringWithFormat:@"invalid or oversized %@ body", media_name];
                    goto cleanup;
                }
            }
            continue;
        }
        if (!PKTLSDeliver(sink, &chunked, is_chunked, &body_finished, buffer, (size_t)ret)) {
            failure = [NSString stringWithFormat:@"invalid or oversized %@ body", media_name];
            goto cleanup;
        }
    }

    if (!parsed_headers) { failure = [NSString stringWithFormat:@"invalid %@ response headers", media_name]; goto cleanup; }
    if (is_chunked && !body_finished) { failure = [NSString stringWithFormat:@"truncated chunked %@ response", media_name]; goto cleanup; }
    if (!is_chunked && (!headers.has_content_length || headers.content_length != sink->written)) {
        failure = [NSString stringWithFormat:@"truncated %@ response", media_name];
        goto cleanup;
    }
    if (!sink->written) { failure = [NSString stringWithFormat:@"empty %@ response", media_name]; goto cleanup; }
    succeeded = YES;

cleanup:
    if (fd >= 0) close(fd);
    mbedtls_ssl_free(&ssl); mbedtls_ssl_config_free(&config); mbedtls_ctr_drbg_free(&drbg);
    mbedtls_entropy_free(&entropy); mbedtls_x509_crt_free(&ca);
    if (!succeeded && error && !*error) *error = PKTLSError(-1001, failure);
    return succeeded;
}

NSData *PKTLSImageGet(NSString *urlString, NSError **error) {
    PKTLSSink sink;
    if (error) *error = nil;
    sink.fd = -1;
    sink.buffer = [NSMutableData data];
    sink.written = 0;
    sink.limit = PKTLS_MAX_IMAGE_BYTES;
    if (!PKTLSFetch([NSURL URLWithString:urlString], &sink, error, 0, PKTLSImage, nil, nil)) return nil;
    return sink.buffer;
}

BOOL PKTLSVideoDownload(NSString *urlString, int fd, NSError **error) {
    PKTLSSink sink;
    if (error) *error = nil;
    if (fd < 0) {
        if (error) *error = PKTLSError(-1002, @"no file to write the video into");
        return NO;
    }
    sink.fd = fd;
    sink.buffer = nil;
    sink.written = 0;
    sink.limit = PKTLS_MAX_VIDEO_BYTES;
    return PKTLSFetch([NSURL URLWithString:urlString], &sink, error, 0, PKTLSVideo, nil, nil);
}

NSData *PKTLSV1Post(NSString *method, NSData *body, NSString *deviceID, NSError **error) {
    if (error) *error = nil;
    NSCharacterSet *badID = [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"] invertedSet];
    if ((![method isEqualToString:@"story.get"] && ![method isEqualToString:@"user.profile.get"]) ||
        !body.length || body.length > 65536 || !deviceID.length || deviceID.length > 128 ||
        [deviceID rangeOfCharacterFromSet:badID].location != NSNotFound) {
        if (error) *error = PKTLSError(-1000, @"invalid public api request");
        return nil;
    }
    PKTLSSink sink;
    sink.fd = -1;
    sink.buffer = [NSMutableData data];
    sink.written = 0;
    sink.limit = PKTLS_MAX_JSON_BYTES;
    NSURL *url = [NSURL URLWithString:[@"https://api.pikabu.ru/v1/" stringByAppendingString:method]];
    if (!PKTLSFetch(url, &sink, error, 0, PKTLSV1, body, deviceID)) return nil;
    return sink.buffer;
}
