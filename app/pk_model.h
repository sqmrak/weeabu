#import <Foundation/Foundation.h>

@interface PKPost : NSObject {
    NSString *_title;
    NSString *_url;
    NSString *_author;
    NSString *_storyID;
    NSString *_summary;
    NSString *_excerpt;
    NSString *_fullText;
    NSString *_parentURL;
    NSString *_parentTitle;
    NSArray *_media;
    NSString *_imageURL;
    NSString *_avatarURL;
    NSString *_community;
    NSString *_date;
    NSArray *_tags;
    NSInteger _score;
    BOOL _scoreKnown;
    double _imageWidth;
    double _imageHeight;
    NSInteger _comments;
    BOOL _hasVideo;
    NSArray *_reactions;
}
@property(nonatomic, retain) NSString *title;
@property(nonatomic, retain) NSString *url;
@property(nonatomic, retain) NSString *author;
@property(nonatomic, retain) NSString *storyID;
@property(nonatomic, retain) NSString *summary;
@property(nonatomic, retain) NSString *excerpt;
@property(nonatomic, retain) NSString *fullText;
@property(nonatomic, retain) NSString *parentURL;
@property(nonatomic, retain) NSString *parentTitle;
@property(nonatomic, retain) NSArray *media;
@property(nonatomic, retain) NSString *imageURL;
@property(nonatomic, retain) NSString *avatarURL;
@property(nonatomic, retain) NSString *community;
@property(nonatomic, retain) NSString *date;
@property(nonatomic, retain) NSArray *tags;
@property(nonatomic, assign) NSInteger score;
@property(nonatomic, assign) BOOL scoreKnown;
@property(nonatomic, assign) double imageWidth;
@property(nonatomic, assign) double imageHeight;
@property(nonatomic, assign) NSInteger comments;
@property(nonatomic, assign) BOOL hasVideo;
@property(nonatomic, retain) NSArray *reactions;
@end

@interface PKComment : NSObject {
    NSArray *_links;
    NSString *_avatarURL;
    NSString *_commentID;
    NSString *_parentID;
    NSString *_author;
    NSString *_body;
    NSString *_date;
    NSString *_mediaURL;
    NSInteger _score;
    BOOL _scoreKnown;
    BOOL _scoreHidden;
    double _mediaWidth;
    double _mediaHeight;
    NSInteger _indent;
    BOOL _mediaIsSticker;
    NSArray *_reactions;
}
@property(nonatomic, retain) NSString *commentID;
@property(nonatomic, retain) NSString *parentID;
@property(nonatomic, retain) NSString *author;
@property(nonatomic, retain) NSString *body;
@property(nonatomic, retain) NSString *date;
@property(nonatomic, retain) NSString *mediaURL;
@property(nonatomic, assign) NSInteger score;
@property(nonatomic, assign) BOOL scoreKnown;
@property(nonatomic, assign) BOOL scoreHidden;
@property(nonatomic, assign) double mediaWidth;
@property(nonatomic, assign) double mediaHeight;
@property(nonatomic, assign) NSInteger indent;
@property(nonatomic, assign) BOOL mediaIsSticker;
@property(nonatomic, retain) NSArray *reactions;
@property(nonatomic, retain) NSArray *links;
@property(nonatomic, retain) NSString *avatarURL;
@end

/* wraps the portable core: parsing rules, bounds and url checks live in core/ under tests/, this file only
   builds foundation objects */

NSArray *PKPostsFromHTML(NSString *html);
/* a text block has "text" and "links", a media block "url", "poster" and "duration" */
NSArray *PKStoryBlocksFromHTML(NSString *html);
/* only the address and the title are known from the feed card, the screen loads the rest */
PKPost *PKParentPost(PKPost *post);
NSArray *PKStoryReactionsFromHTML(NSString *html);
NSString *PKCSRFTokenFromHTML(NSString *html);
BOOL PKStoryScoreFromHTML(NSString *html, NSInteger *score);
NSArray *PKCommentsFromHTML(NSString *html);
NSArray *PKCommentIDsFromHTML(NSString *html);

void PKAppendUniquePosts(NSMutableArray *destination, NSArray *posts);
NSString *PKReactionSummary(NSArray *reactions, NSUInteger limit);
NSString *PKCompactScore(NSInteger value);
