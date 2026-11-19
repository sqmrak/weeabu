#import <UIKit/UIKit.h>

@interface PKLoginViewController : UIViewController
- (id)initWithCompletion:(void (^)(BOOL authenticated))completion;
@end
