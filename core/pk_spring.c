#include "pk_spring.h"

#include <math.h>

static int token(pk_spring_kind kind, double *stiffness, double *ratio) {
    switch (kind) {
    case PK_SPRING_SPATIAL: *stiffness = 700.0; *ratio = 0.6; return 1;
    case PK_SPRING_SPATIAL_FAST: *stiffness = 1400.0; *ratio = 0.6; return 1;
    case PK_SPRING_SPATIAL_SLOW: *stiffness = 300.0; *ratio = 0.6; return 1;
    case PK_SPRING_EFFECTS: *stiffness = 1600.0; *ratio = 1.0; return 1;
    }
    return 0;
}

static double damped(double seconds, double stiffness, double ratio) {
    double frequency = sqrt(stiffness);
    double decay = frequency * ratio;
    if (ratio >= 1.0) return 1.0 - exp(-decay * seconds) * (1.0 + decay * seconds);
    double oscillation = frequency * sqrt(1.0 - ratio * ratio);
    return 1.0 - exp(-decay * seconds) * (cos(oscillation * seconds) + decay / oscillation * sin(oscillation * seconds));
}

double pk_spring_duration(pk_spring_kind kind) {
    double stiffness, ratio;
    if (!token(kind, &stiffness, &ratio)) return 0.0;
    /* searched backwards from a bound, so a late swing back past the band is not cut */
    double seconds = 1.5;
    while (seconds > 0.0 && fabs(1.0 - damped(seconds, stiffness, ratio)) <= 0.001) seconds -= 0.002;
    return seconds + 0.002;
}

double pk_spring_progress(pk_spring_kind kind, double share) {
    double stiffness, ratio;
    if (!token(kind, &stiffness, &ratio)) return 0.0;
    if (!isfinite(share) || share <= 0.0) return 0.0;
    if (share >= 1.0) return 1.0;
    double span = pk_spring_duration(kind);
    return damped(share * span, stiffness, ratio) / damped(span, stiffness, ratio);
}
