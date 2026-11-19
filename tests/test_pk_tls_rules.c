#include <assert.h>
#include <string.h>

#include "pk_tls_rules.h"

/* the same bytes are decoded once as one buffer and once split at every tls record boundary */
static int decode_chunked(const char *wire, size_t wire_length, size_t step,
                          size_t out_capacity, char *out, size_t *out_length) {
    PKTLSChunked decoder;
    size_t offset = 0;
    int result = PKTLS_CHUNK_MORE;
    *out_length = 0;
    PKTLSChunkedInit(&decoder, 1024 * 1024);
    while (offset < wire_length) {
        size_t slice = wire_length - offset < step ? wire_length - offset : step;
        size_t consumed = 0;
        do {
            size_t taken = 0;
            size_t produced = 0;
            result = PKTLSChunkedFeed(&decoder,
                                      (const unsigned char *)wire + offset + consumed, slice - consumed, &taken,
                                      (unsigned char *)out + *out_length, out_capacity - *out_length, &produced);
            *out_length += produced;
            consumed += taken;
            if (result == PKTLS_CHUNK_ERROR) return result;
            if (result == PKTLS_CHUNK_DONE) return result;
            if (!taken && !produced) break;
        } while (consumed < slice);
        offset += slice;
    }
    return result;
}

static void check_chunked(const char *wire, const char *expected) {
    size_t step;
    for (step = 1; step <= strlen(wire); step++) {
        char out[512];
        size_t length = 0;
        assert(decode_chunked(wire, strlen(wire), step, sizeof(out), out, &length) == PKTLS_CHUNK_DONE);
        assert(length == strlen(expected));
        assert(!memcmp(out, expected, length));
    }
}

static void check_chunked_rejected(const char *wire) {
    char out[512];
    size_t length = 0;
    assert(decode_chunked(wire, strlen(wire), strlen(wire), sizeof(out), out, &length) != PKTLS_CHUNK_DONE);
}

static void test_chunked_stream(void) {
    check_chunked("3\r\nabc\r\n2\r\nde\r\n0\r\n\r\n", "abcde");
    check_chunked("0\r\n\r\n", "");
    /* the length is hex, and an extension after it carries no body */
    check_chunked("A\r\n0123456789\r\n0\r\n\r\n", "0123456789");
    check_chunked("3;name=value\r\nabc\r\n0\r\n\r\n", "abc");
    /* a trailer is read to its end and contributes nothing */
    check_chunked("3\r\nabc\r\n0\r\nX-Trailer: 1\r\n\r\n", "abc");

    /* a body that stops early is not a body */
    check_chunked_rejected("3\r\nab");
    check_chunked_rejected("3\r\nabc\r\n");
    check_chunked_rejected("3\r\nabc\r\n0\r\n");
    /* the crlf after the data is part of the framing */
    check_chunked_rejected("3\r\nabcXX0\r\n\r\n");
    check_chunked_rejected("zz\r\nabc\r\n0\r\n\r\n");
    check_chunked_rejected("\r\n0\r\n\r\n");
    /* a length past what a size_t holds is refused, not wrapped */
    check_chunked_rejected("FFFFFFFFFFFFFFFFFF\r\nx\r\n0\r\n\r\n");
}

static void test_chunked_limit(void) {
    PKTLSChunked decoder;
    const char wire[] = "8\r\n01234567\r\n0\r\n\r\n";
    unsigned char out[64];
    size_t consumed = 0;
    size_t produced = 0;
    /* the cap is the decoder's own, not the caller's buffer size */
    PKTLSChunkedInit(&decoder, 4);
    assert(PKTLSChunkedFeed(&decoder, (const unsigned char *)wire, sizeof(wire) - 1, &consumed,
                            out, sizeof(out), &produced) == PKTLS_CHUNK_ERROR);
    /* once it has failed it stays failed */
    assert(PKTLSChunkedFeed(&decoder, (const unsigned char *)wire, sizeof(wire) - 1, &consumed,
                            out, sizeof(out), &produced) == PKTLS_CHUNK_ERROR);
}

static void test_chunked_small_output(void) {
    PKTLSChunked decoder;
    const char wire[] = "6\r\nabcdef\r\n0\r\n\r\n";
    char collected[16];
    size_t length = 0;
    size_t offset = 0;
    int result = PKTLS_CHUNK_MORE;
    PKTLSChunkedInit(&decoder, 1024);
    /* a caller with a two byte window still gets every byte, in order */
    while (result == PKTLS_CHUNK_MORE) {
        unsigned char window[2];
        size_t consumed = 0;
        size_t produced = 0;
        result = PKTLSChunkedFeed(&decoder, (const unsigned char *)wire + offset, sizeof(wire) - 1 - offset,
                                  &consumed, window, sizeof(window), &produced);
        memcpy(collected + length, window, produced);
        length += produced;
        offset += consumed;
        assert(consumed || produced);
    }
    assert(result == PKTLS_CHUNK_DONE);
    assert(length == 6 && !memcmp(collected, "abcdef", 6));
}

int main(void) {
    test_chunked_stream();
    test_chunked_limit();
    test_chunked_small_output();
    PKTLSHTTPHeaders headers;
    size_t output_length = 0;
    unsigned char output[32];
    const unsigned char valid[] = "HTTP/1.1 200 OK\r\nContent-Type: image/webp\r\nContent-Length: 3\r\n\r\nxyz";
    const unsigned char chunked[] = "3\r\nabc\r\n2\r\nde\r\n0\r\n\r\n";
    unsigned char large_response[PKTLS_MAX_HEADER_BYTES + 128];
    const unsigned char large_header[] = "HTTP/1.1 200 OK\r\nContent-Type: video/mp4\r\nContent-Length: 32791\r\n\r\n";
    assert(PKTLSHostAllowed("pikabu.ru"));
    assert(PKTLSHostAllowed("cdn.pikabu.ru"));
    assert(!PKTLSHostAllowed("pikabu.ru.attacker.example"));
    assert(!PKTLSHostAllowed("notpikabu.ru"));
    assert(!PKTLSHostAllowed("pikabu.ru."));
    assert(PKTLSParseHTTPHeaders(valid, sizeof(valid) - 1, &headers));
    assert(headers.status == 200 && headers.image_content_type && headers.has_content_length && headers.content_length == 3);
    {
        const unsigned char json[] = "HTTP/1.1 200 OK\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: 2\r\n\r\n{}";
        const unsigned char html[] = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 2\r\n\r\n{}";
        assert(PKTLSParseHTTPHeaders(json, sizeof(json) - 1, &headers) && headers.json_content_type);
        assert(PKTLSParseHTTPHeaders(html, sizeof(html) - 1, &headers) && !headers.json_content_type);
        const unsigned char duplicate[] = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Type: application/json\r\nContent-Length: 2\r\n\r\n{}";
        assert(!PKTLSParseHTTPHeaders(duplicate, sizeof(duplicate) - 1, &headers));
    }
    assert(!PKTLSParseHTTPHeaders((const unsigned char *)"HTTP/1.1 200 OK\r\nContent-Length: nope\r\n\r\n", 43, &headers));
    memcpy(large_response, large_header, sizeof(large_header) - 1);
    memset(large_response + sizeof(large_header) - 1, 0, sizeof(large_response) - sizeof(large_header) + 1);
    assert(PKTLSParseHTTPHeaders(large_response, sizeof(large_response), &headers));
    assert(headers.video_content_type && headers.content_length == 32791);
    assert(PKTLSDecodeChunked(chunked, sizeof(chunked) - 1, output, sizeof(output), &output_length));
    assert(output_length == 5 && !memcmp(output, "abcde", 5));
    assert(!PKTLSDecodeChunked((const unsigned char *)"3\r\nab", 5, output, sizeof(output), &output_length));
    return 0;
}
