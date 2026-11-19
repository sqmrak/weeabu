#include <assert.h>
#include <math.h>
#include "pk_media_layout.h"

int main(void) {
    assert(pk_media_height(320, 640, 480) == 240);
    assert(pk_media_height(320, 100, 1000) == 3200);
    assert(pk_media_height(320, 1000, 100) == 32);
    assert(pk_media_height(320, 1, 1000000) == 8192);
    assert(pk_media_height(0, 1, 1) == 0);
    assert(pk_media_height(320, 0, 1) == 0);
    assert(pk_media_height(320, 1, 0) == 0);
    assert(pk_media_height(NAN, 1, 1) == 0);
    assert(pk_media_height(320, INFINITY, 1) == 0);
    return 0;
}
