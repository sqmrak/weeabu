#import <UIKit/UIKit.h>
#import "pk_model.h"
@interface StoryViewController : UIViewController
- (id)initWithPost:(PKPost *)post;
/* unfolds the branches above the comment, scrolls to it and marks it */
- (id)initWithPost:(PKPost *)post focusCommentID:(NSString *)commentID;
@end
