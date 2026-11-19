#include "test_util.h"
#include "pk_spring.h"
#include <math.h>

int main(void) {
    static const pk_spring_kind kinds[] = { PK_SPRING_SPATIAL, PK_SPRING_SPATIAL_FAST, PK_SPRING_SPATIAL_SLOW, PK_SPRING_EFFECTS };
    for (unsigned i = 0; i < sizeof kinds / sizeof kinds[0]; ++i) {
        pk_spring_kind kind = kinds[i];
        double duration = pk_spring_duration(kind);
        /* a spring that settles in a fraction of a second, never in an instant and never in a long drift */
        CHECK(duration > 0.1 && duration < 0.7);
        /* exact ends, and a share outside 0..1 or not a number stays on them */
        CHECK(pk_spring_progress(kind, 0) == 0);
        CHECK(pk_spring_progress(kind, 1) == 1);
        CHECK(pk_spring_progress(kind, -3) == 0);
        CHECK(pk_spring_progress(kind, 7) == 1);
        CHECK(pk_spring_progress(kind, NAN) == 0);
        CHECK(pk_spring_progress(kind, INFINITY) == 0);
        double peak = 0, previous = 0;
        for (int step = 1; step <= 400; ++step) {
            double value = pk_spring_progress(kind, step / 400.0);
            CHECK(isfinite(value));
            if (value > peak) peak = value;
            if (kind == PK_SPRING_EFFECTS) CHECK(value <= 1.0000001 && value >= previous - 1e-9);
            previous = value;
        }
        /* the expressive springs pass their target by about a tenth, the effects spring does not pass it */
        if (kind == PK_SPRING_EFFECTS) CHECK(peak <= 1.0000001);
        else CHECK(peak > 1.05 && peak < 1.15);
    }
    /* a stiffer spring settles sooner */
    CHECK(pk_spring_duration(PK_SPRING_SPATIAL_FAST) < pk_spring_duration(PK_SPRING_SPATIAL));
    CHECK(pk_spring_duration(PK_SPRING_SPATIAL) < pk_spring_duration(PK_SPRING_SPATIAL_SLOW));
    CHECK(pk_spring_duration((pk_spring_kind)99) == 0);
    CHECK(pk_spring_progress((pk_spring_kind)99, 0.5) == 0);
    return test_finish("test_pk_spring");
}
