#import <UIKit/UIKit.h>


@interface PKAwardsViewController : UITableViewController
- (id)initWithAwards:(NSArray *)awards name:(NSString *)name;
@end

@interface PKCommunitiesViewController : UITableViewController
- (id)initWithCommunities:(NSArray *)communities name:(NSString *)name;
@end

@interface PKUserPostsViewController : UITableViewController
- (id)initWithUsername:(NSString *)username;
@end

/* needs the api session */
@interface PKMyCommentsViewController : UITableViewController
@end

/* needs the api session */
@interface PKNotificationsViewController : UITableViewController
@end
