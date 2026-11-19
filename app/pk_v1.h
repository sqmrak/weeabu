#import <Foundation/Foundation.h>

typedef void (^PKV1Completion)(id response, NSError *error);

/* completion runs on the main thread, server errors keep message_code */
void PKV1Request(NSString *method, NSDictionary *parameters, PKV1Completion completion);
/* a reply with no body is a success */
void PKV1Action(NSString *method, NSDictionary *parameters, void (^completion)(NSError *error));
void PKV1Feed(NSString *feed, NSInteger page, PKV1Completion completion);
void PKV1Search(NSString *query, NSInteger page, PKV1Completion completion);
void PKV1Story(NSNumber *storyID, NSInteger page, PKV1Completion completion);
void PKV1SignIn(NSString *username, NSString *password, PKV1Completion completion);
void PKV1SignOut(PKV1Completion completion);
/* a site sign-in does not open it, and every call that names a user answers 401 until it is open */
BOOL PKV1IsUnauthorized(NSError *error);
/* the password is used for this one call and kept nowhere */
void PKV1Reauthenticate(NSString *password, void (^completion)(NSError *error));
void PKV1Profile(NSString *username, NSNumber *currentUserID, PKV1Completion completion);
void PKV1ProfileRating(NSString *username, void (^completion)(NSString *rating, BOOL negative, NSError *error));
void PKV1CommentChildren(NSNumber *commentID, NSNumber *userID, PKV1Completion completion);
void PKV1CreateComment(NSNumber *storyID, NSNumber *userID, NSNumber *parentID,
                       NSString *text, BOOL plainText, NSArray *images, PKV1Completion completion);
void PKV1Vote(NSString *type, NSNumber *itemID, NSNumber *userID, NSInteger vote, PKV1Completion completion);
