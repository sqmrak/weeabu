#include "pk_media_layout.h"

double pk_media_height(double display_width, double image_width, double image_height) {
    double height;
    if (!(display_width > 0.0) || !(image_width > 0.0) || !(image_height > 0.0) ||
        display_width > 10000.0 || image_width > 1000000.0 || image_height > 1000000.0) return 0.0;
    height = display_width * (image_height / image_width);
    if (!(height > 0.0)) return 0.0;
    /* a very long image fits without cropping */
    return height > 8192.0 ? 8192.0 : height;
}
