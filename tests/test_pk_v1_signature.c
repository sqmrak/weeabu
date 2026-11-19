#include <assert.h>
#include <openssl/evp.h>
#include <stdio.h>
#include <string.h>
#include "pk_v1_signature.h"
static int digest(const unsigned char *data, size_t length, unsigned char *out) {
    unsigned int size = 0;
    return EVP_Digest(data, length, out, &size, EVP_md5(), NULL) == 1 && size == 16 ? 0 : -1;
}
static int fail_digest(const unsigned char *data, size_t length, unsigned char *out) {
    (void)data; (void)length; (void)out; return -1;
}
int main(void) {
    char result[45], large[17000];
    assert(pk_v1_signature("feed", "1600000000000", "1,1,hot", digest, result, sizeof(result)));
    assert(strcmp(result, "MGFkNTBkZDhiNjNjNjQ4ZDIyYjExNzQ3YjJmZmE4YzA=") == 0);
    assert(!pk_v1_signature("feed", "1", "1", digest, result, 44));
    assert(!pk_v1_signature("feed", "1", "1", fail_digest, result, sizeof(result)) && !result[0]);
    memset(large, 'a', sizeof(large)); large[sizeof(large)-1] = 0;
    assert(!pk_v1_signature("feed", "1", large, digest, result, sizeof(result)) && !result[0]);
    return 0;
}
