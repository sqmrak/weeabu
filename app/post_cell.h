#import <UIKit/UIKit.h>
#import "pk_model.h"

@class PKPostCell;

@protocol PKPostCellDelegate <NSObject>
- (void)postCellDidToggleExpanded:(PKPostCell *)cell;
- (void)postCellDidOpenMedia:(PKPostCell *)cell;
- (void)postCellDidOpenParent:(PKPostCell *)cell;
- (void)postCell:(PKPostCell *)cell didTapTag:(NSString *)tag;
@optional
- (void)postCell:(PKPostCell *)cell didTapAuthor:(NSString *)author;
@end

@interface PKPostCell : UITableViewCell
- (void)setPost:(PKPost *)post expanded:(BOOL)expanded
       delegate:(id<PKPostCellDelegate>)delegate;
- (BOOL)isExpanded;
- (PKPost *)post;
@end

/* the feed, the search list and the cell lay out from this one function, so they cannot drift apart */
CGFloat PKPostCellHeightForWidth(PKPost *post, BOOL expanded, CGFloat width);

/* a tap on the preview needs no trip through the post screen */
void PKPresentPostMedia(UIViewController *presenter, PKPost *post);

void PKOpenParentPost(UINavigationController *navigation, PKPost *post);
