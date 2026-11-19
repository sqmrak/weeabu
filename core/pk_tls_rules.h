#ifndef PK_TLS_RULES_H
#define PK_TLS_RULES_H

#include <stddef.h>

#define PKTLS_MAX_HEADER_BYTES (32 * 1024)

typedef struct {
    int status;
    size_t header_length;
    size_t content_length;
    int has_content_length;
    int chunked;
    int image_content_type;
    int video_content_type;
    int json_content_type;
} PKTLSHTTPHeaders;

/* a video is too big to hold whole before decoding, so chunked encoding is peeled off as bytes arrive, the
   caller owns the buffer */
enum {
    PKTLS_CHUNK_MORE = 0,   /* fed everything given, more input expected */
    PKTLS_CHUNK_DONE,       /* the terminating chunk and its trailer are read */
    PKTLS_CHUNK_ERROR       /* the framing is malformed or the cap was crossed */
};

/* hex digits only, so a length cannot be padded past size_t */
#define PKTLS_MAX_CHUNK_DIGITS 12
/* a trailer nobody reads still has to end */
#define PKTLS_MAX_TRAILER_BYTES 4096

typedef struct {
    int state;
    size_t chunk_remaining;
    size_t digits;
    size_t produced;
    size_t limit;
    size_t trailer_bytes;
} PKTLSChunked;

void PKTLSChunkedInit(PKTLSChunked *decoder, size_t limit);

/* the caller loops while the return is PKTLS_CHUNK_MORE and `consumed` is short of `length` */
int PKTLSChunkedFeed(PKTLSChunked *decoder,
                     const unsigned char *input, size_t length, size_t *consumed,
                     unsigned char *out, size_t out_capacity, size_t *produced);

int PKTLSHostAllowed(const char *host);
int PKTLSParseHTTPHeaders(const unsigned char *data, size_t length, PKTLSHTTPHeaders *headers);
int PKTLSDecodeChunked(const unsigned char *input, size_t input_length,
                       unsigned char *output, size_t output_capacity, size_t *output_length);

#endif
