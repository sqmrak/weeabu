#import <UIKit/UIKit.h>

/* covers the whole screen, tab bar included, and turns with its host */

typedef void (^PKDialogHandler)(NSInteger index);

/* the handler gets -1 for a tap outside the card when cancelable is YES */
void PKShowAlert(NSString *title, NSString *message, NSArray *buttons, NSInteger destructive, BOOL cancelable, PKDialogHandler handler);
void PKShowNotice(NSString *title, NSString *message);
/* the handler gets -1 for cancel and for a tap outside */
void PKShowSheet(NSString *title, NSArray *items, NSInteger destructive, NSString *cancel, PKDialogHandler handler);
/* the handler gets nil for cancel */
void PKShowPasswordPrompt(NSString *title, NSString *message, NSString *confirm, void (^handler)(NSString *password));
/* a host with gesture recognizers must refuse touches inside a dialog, or the recognizer cancels them
   before a button sees the tap */
BOOL PKViewIsInDialog(UIView *view);
