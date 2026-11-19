#import <UIKit/UIKit.h>

@interface PKMediaViewer : UIViewController <UIScrollViewDelegate, UIGestureRecognizerDelegate>
- (id)initWithMedia:(NSArray *)media title:(NSString *)title index:(NSUInteger)index;
- (id)initWithImageURLs:(NSArray *)urls title:(NSString *)title index:(NSUInteger)index;
- (id)initWithVideoURL:(NSURL *)url title:(NSString *)title;
@end
