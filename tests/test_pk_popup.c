#include "test_util.h"
#include "pk_popup.h"
#include <math.h>

int main(void) {
    for (int entering = 0; entering <= 1; ++entering) {
        double duration = pk_popup_duration(entering);
        CHECK(duration > 0.1 && duration < 0.5);
        CHECK(pk_popup_progress(entering, 0) == 0);
        CHECK(pk_popup_progress(entering, 1) == 1);
        CHECK(pk_popup_progress(entering, -2) == 0);
        CHECK(pk_popup_progress(entering, 9) == 1);
        CHECK(pk_popup_progress(entering, NAN) == 0);
        CHECK(pk_popup_progress(entering, INFINITY) == 0);
        double previous = 0;
        for (int step = 1; step <= 500; ++step) {
            double value = pk_popup_progress(entering, step / 500.0);
            /* never past the target and never back: the window must not swing or rise while it leaves */
            CHECK(isfinite(value) && value >= previous - 1e-9 && value <= 1.0 + 1e-9);
            previous = value;
        }
    }
    /* the way in decelerates, the way out accelerates */
    CHECK(pk_popup_progress(1, 0.25) > 0.5);
    CHECK(pk_popup_progress(0, 0.25) < 0.25);
    CHECK(pk_popup_duration(1) > pk_popup_duration(0));
    return test_finish("test_pk_popup");
}
