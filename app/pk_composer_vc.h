#import <UIKit/UIKit.h>
#import "pk_model.h"

/* completion runs after the site took the comment and the screen is gone */
@interface PKComposerViewController : UIViewController <UITextViewDelegate>
- (id)initWithStory:(PKPost *)post parent:(PKComment *)parent completion:(void (^)(void))completion;
@end
