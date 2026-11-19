#ifndef PK_MEDIA_DRAG_H
#define PK_MEDIA_DRAG_H

/* one gesture must not page and dismiss */
typedef enum pk_media_drag_direction {
    PK_MEDIA_DRAG_NONE,
    PK_MEDIA_DRAG_HORIZONTAL,
    PK_MEDIA_DRAG_VERTICAL
} pk_media_drag_direction;

pk_media_drag_direction pk_media_drag_direction_for(double x, double y);
double pk_media_drag_progress(double distance, double height);
int pk_media_drag_should_close(double distance, double height, int ended);

#endif
