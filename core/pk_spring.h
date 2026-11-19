#ifndef PK_SPRING_H
#define PK_SPRING_H

/* spatial springs have damping 0.6 and overshoot by about a tenth, the effects spring is critically damped */
typedef enum {
    PK_SPRING_SPATIAL,
    PK_SPRING_SPATIAL_FAST,
    PK_SPRING_SPATIAL_SLOW,
    PK_SPRING_EFFECTS
} pk_spring_kind;

double pk_spring_duration(pk_spring_kind kind);
/* 0 for a share that is not a number and for an unknown kind */
double pk_spring_progress(pk_spring_kind kind, double share);

#endif
