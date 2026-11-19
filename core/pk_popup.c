#include "pk_popup.h"

#include <math.h>

static double cubic(double t, double first, double second) {
    double inverse = 1.0 - t;
    return 3.0 * inverse * inverse * t * first + 3.0 * inverse * t * t * second + t * t * t;
}

static double bezier(double share, double x1, double y1, double x2, double y2) {
    double lower = 0.0, upper = 1.0;
    /* an end of the bezier without a slope would never converge */
    for (int i = 0; i < 32; ++i) {
        double middle = (lower + upper) * 0.5;
        if (cubic(middle, x1, x2) < share) lower = middle;
        else upper = middle;
    }
    return cubic((lower + upper) * 0.5, y1, y2);
}

double pk_popup_duration(int entering) {
    return entering ? 0.34 : 0.2;
}

double pk_popup_progress(int entering, double share) {
    if (!isfinite(share) || share <= 0.0) return 0.0;
    if (share >= 1.0) return 1.0;
    return entering ? bezier(share, 0.05, 0.7, 0.1, 1.0) : bezier(share, 0.3, 0.0, 0.8, 0.15);
}
