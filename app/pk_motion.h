#import <UIKit/UIKit.h>

#include "pk_spring.h"
#include "pk_popup.h"

NSTimeInterval PKMotionDuration(NSTimeInterval duration);
void PKAnimatePress(UIView *view);
/* a later call under the same key replaces a run that has not ended, nothing plays off screen or with
   reduce motion on */
void PKAnimateSpring(UIView *view, CGAffineTransform from, CGFloat fromAlpha, pk_spring_kind kind, NSTimeInterval delay, NSString *key);
/* starts from what the layer shows now, so a window closed mid-arrival leaves from where it is. completion
   gets NO when a later call replaced the move */
void PKAnimatePopup(UIView *view, CGAffineTransform transform, CGFloat alpha, BOOL entering, void (^completion)(BOOL finished));
/* a layout pass that wrote the frame of a moved view shifted the window by the size of the move for one
   frame, a jump before it left */
void PKPlaceView(UIView *view, CGRect frame);
void PKPopView(UIView *view, CGFloat from);
void PKAnimateTab(UIView *view);

void PKAttachPressFeedback(UIControl *control);
void PKAnimateListAppearance(UITableView *tableView);
void PKAnimateThemeChange(UIView *view);
