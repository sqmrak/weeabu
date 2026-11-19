#import <Foundation/Foundation.h>
#import "pk_model.h"
#import "pk_api.h"

@interface PKAward : NSObject {
    NSString *_title;
    NSString *_imageURL;
    NSString *_date;
    NSString *_storyTitle;
    NSString *_link;
}
@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *imageURL;
@property(nonatomic, copy) NSString *date;
@property(nonatomic, copy) NSString *storyTitle;
/* "" when it was given for nothing in particular */
@property(nonatomic, copy) NSString *link;
@end

@interface PKCommunity : NSObject {
    NSString *_name;
    NSString *_link;
    NSString *_avatarURL;
}
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *link;
@property(nonatomic, copy) NSString *avatarURL;
@end

/* every field is type checked on read, what the server left out or sent in another shape is empty or zero */
@interface PKUserProfile : NSObject {
    NSNumber *_userID;
    NSString *_name;
    NSString *_avatarURL;
    NSString *_headerURL;
    NSString *_approved;
    NSString *_about;
    NSString *_rating;
    NSString *_registration;
    BOOL _ratingNegative;
    NSInteger _comments;
    NSInteger _stories;
    NSInteger _hotStories;
    NSInteger _pluses;
    NSInteger _minuses;
    NSInteger _subscribers;
    NSArray *_awards;
    NSArray *_communities;
    BOOL _subscribed;
    BOOL _ignored;
}
@property(nonatomic, retain) NSNumber *userID;
@property(nonatomic, copy) NSString *name;
@property(nonatomic, copy) NSString *avatarURL;
@property(nonatomic, copy) NSString *headerURL;
@property(nonatomic, copy) NSString *approved;
@property(nonatomic, copy) NSString *about;
@property(nonatomic, copy) NSString *rating;
@property(nonatomic, copy) NSString *registration;
@property(nonatomic, assign) BOOL ratingNegative;
@property(nonatomic, assign) NSInteger comments;
@property(nonatomic, assign) NSInteger stories;
@property(nonatomic, assign) NSInteger hotStories;
@property(nonatomic, assign) NSInteger pluses;
@property(nonatomic, assign) NSInteger minuses;
@property(nonatomic, assign) NSInteger subscribers;
@property(nonatomic, retain) NSArray *awards;
@property(nonatomic, retain) NSArray *communities;
@property(nonatomic, assign) BOOL subscribed;
@property(nonatomic, assign) BOOL ignored;
+ (PKUserProfile *)profileFromResponse:(id)response;
- (NSString *)pageURL;
@end

typedef void (^PKProfileCompletion)(PKUserProfile *profile, NSError *error);
void PKLoadUserProfile(NSString *username, PKProfileCompletion completion);
/* the author's page on the site is the same list of cards as the feed */
void PKLoadUserPosts(NSString *username, NSInteger page, PKPostsCompletion completion);

NSString *PKPlainTextFromHTML(NSString *html);

/* a failure with PKV1IsUnauthorized(error) means the api session is not open (see pk_v1.h) */

/* read once from the public profile and kept for the run */
void PKCurrentUserID(void (^completion)(NSNumber *userID, NSError *error));
/* only the server's answer changes the state */
void PKSetSubscribed(NSNumber *authorID, BOOL subscribed, void (^completion)(NSError *error));
void PKSetIgnored(NSNumber *authorID, BOOL ignored, void (^completion)(NSError *error));
/* the password is not kept */
void PKPromptApiSession(void (^completion)(BOOL opened));

@interface PKMyComment : NSObject {
    NSString *_text;
    NSString *_storyTitle;
    NSString *_storyURL;
    NSString *_storyID;
    NSString *_commentID;
    NSString *_parentAuthor;
    NSString *_parentText;
    long _time;
    NSInteger _rating;
}
@property(nonatomic, copy) NSString *text;
@property(nonatomic, copy) NSString *storyTitle;
@property(nonatomic, copy) NSString *storyURL;
@property(nonatomic, copy) NSString *storyID;
@property(nonatomic, copy) NSString *commentID;
@property(nonatomic, copy) NSString *parentAuthor;
@property(nonatomic, copy) NSString *parentText;
@property(nonatomic, assign) long time;
@property(nonatomic, assign) NSInteger rating;
@end

/* 1 is by time, 2 by what is still being discussed */
void PKLoadMyComments(NSNumber *userID, NSInteger sort, NSInteger page, void (^completion)(NSArray *comments, NSError *error));

@interface PKNotice : NSObject {
    NSString *_text;
    NSString *_date;
    NSString *_type;
    BOOL _isNew;
}
@property(nonatomic, copy) NSString *text;
@property(nonatomic, copy) NSString *date;
@property(nonatomic, copy) NSString *type;
@property(nonatomic, assign) BOOL isNew;
@end

void PKLoadNotifications(NSNumber *userID, void (^completion)(NSArray *notices, NSError *error));
void PKNotificationAction(NSNumber *userID, NSString *action, void (^completion)(NSError *error));
