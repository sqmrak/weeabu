#ifndef PK_PHOTO_ZOOM_H
#define PK_PHOTO_ZOOM_H


#define PK_PHOTO_ZOOM_MAX 6.0

/* (x, y) is the picture center measured from the middle of the viewing area */

/* keeps the spot under the focal point where it was when the zoom changes */
int pk_photo_zoom_about(double zoom, double x, double y, double focal_x, double focal_y, double new_zoom, double *new_x, double *new_y);
/* covers the area on every axis where the picture is larger, centers it on the others */
int pk_photo_zoom_clamp(double image_width, double image_height, double area_width, double area_height, double min_zoom,
                                      double *zoom, double *x, double *y);

#endif
