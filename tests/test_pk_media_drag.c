#include "test_util.h"
#include "pk_media_drag.h"
#include <math.h>

int main(void) {
    CHECK_EQ_INT(pk_media_drag_direction_for(0, 0), PK_MEDIA_DRAG_NONE);
    CHECK_EQ_INT(pk_media_drag_direction_for(3, -4), PK_MEDIA_DRAG_VERTICAL);
    CHECK_EQ_INT(pk_media_drag_direction_for(-4, 3), PK_MEDIA_DRAG_HORIZONTAL);
    CHECK_EQ_INT(pk_media_drag_direction_for(4, 4), PK_MEDIA_DRAG_HORIZONTAL);
    CHECK_EQ_INT(pk_media_drag_direction_for(NAN, 1), PK_MEDIA_DRAG_NONE);
    CHECK(pk_media_drag_progress(0, 600) == 0);
    CHECK(pk_media_drag_progress(-150, 600) == 0.5);
    CHECK(pk_media_drag_progress(900, 600) == 1);
    CHECK(pk_media_drag_progress(10, 0) == 0);
    CHECK(!pk_media_drag_should_close(100, 600, 1));
    CHECK(pk_media_drag_should_close(101, 600, 1));
    CHECK(pk_media_drag_should_close(-101, 600, 1));
    CHECK(!pk_media_drag_should_close(101, 600, 0));
    CHECK(!pk_media_drag_should_close(NAN, 600, 1));
    return test_finish("test_media_drag");
}
