#import <UIKit/UIKit.h>

typedef enum {
    PKIconArrowUp = 0,
    PKIconArrowDown,
    PKIconComment,
    PKIconShare,
    PKIconPlay,
    PKIconBack,
    PKIconRefresh
} PKIconKind;

/* no rasters: sharp at every scale and tinted by the theme without a second asset */
UIImage *PKIcon(PKIconKind kind, CGFloat size, UIColor *color);

UIBarButtonItem *PKIconBarItem(PKIconKind kind, NSString *label, id target, SEL action);
