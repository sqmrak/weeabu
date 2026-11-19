#ifndef PK_POPUP_H
#define PK_POPUP_H

/* material 3 emphasized curves as in ios/exteria: slow in, short and sharp out, never past the target */

double pk_popup_duration(int entering);
/* 0 for a share that is not a number */
double pk_popup_progress(int entering, double share);

#endif
