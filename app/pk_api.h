#import <Foundation/Foundation.h>
#import "pk_model.h"

typedef void (^PKPostsCompletion)(NSArray *posts, NSError *error);
typedef void (^PKStoryCompletion)(NSString *html, NSError *error);
typedef void (^PKCommentsCompletion)(NSArray *comments, NSError *error);
typedef void (^PKActionCompletion)(NSError *error);
typedef void (^PKCommentScoresCompletion)(NSDictionary *scores, BOOL finished, NSError *error);

void PKLoadFeed(NSString *section, NSInteger page, PKPostsCompletion completion);
void PKSearch(NSString *query, NSInteger page, PKPostsCompletion completion);
void PKLoadStory(PKPost *post, PKStoryCompletion completion);
void PKLoadComments(PKPost *post, NSString *storyHTML, PKCommentsCompletion completion);
void PKLoadHiddenCommentScores(PKPost *post, NSArray *comments, PKCommentScoresCompletion completion);
void PKVoteStory(PKPost *post, NSInteger vote, NSString *storyHTML, PKActionCompletion completion);
void PKVoteComment(PKComment *comment, NSInteger vote, NSString *storyHTML, PKActionCompletion completion);
void PKReactStory(PKPost *post, NSInteger reactionID, BOOL add, NSString *storyHTML, PKActionCompletion completion);
void PKReactComment(PKComment *comment, NSInteger reactionID, BOOL add, NSString *storyHTML, PKActionCompletion completion);
