#import <UIKit/UIKit.h>

/* the host argument stays for callers that pass a view, the sheet covers the whole screen */
void PKPresentShareSheet(UIView *host, NSString *title, NSString *url);
