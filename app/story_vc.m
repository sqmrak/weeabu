#import "story_vc.h"
#import "pk_lang.h"
#import "pk_api.h"
#import "pk_auth.h"
#import "pk_theme.h"
#import "pk_motion.h"
#include "pk_media_layout.h"
#import "pk_emoji_label.h"
#import "pk_icons.h"
#import "pk_share.h"
#import "login_vc.h"
#import "profile_vc.h"
#import "pk_image.h"
#import "pk_image_viewer.h"
#import "pk_composer_vc.h"
#import "pk_dialog.h"
#import <QuartzCore/QuartzCore.h>

@interface PKReactionPicker : UIView {
    UIView *_panel;
    NSArray *_titles;
    void (^_selection)(NSInteger index);
}
- (id)initWithTitles:(NSArray *)titles selection:(void (^)(NSInteger index))selection;
- (void)presentInView:(UIView *)view;
@end

@implementation PKReactionPicker
- (id)initWithTitles:(NSArray *)titles selection:(void (^)(NSInteger index))selection {
    if ((self = [super initWithFrame:CGRectZero])) {
        _titles = [titles copy];
        _selection = [selection copy];
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45f];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        UIButton *backdrop = [UIButton buttonWithType:UIButtonTypeCustom];
        backdrop.frame = self.bounds;
        backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [backdrop addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:backdrop];
        _panel = [[UIView alloc] initWithFrame:CGRectZero];
        _panel.backgroundColor = PKCardColor();
        _panel.layer.cornerRadius = 16;
        _panel.clipsToBounds = YES;
        [self addSubview:_panel];
        for (NSUInteger i = 0; i < _titles.count; i++) {
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
            button.tag = (NSInteger)i;
            button.backgroundColor = PKControlColor();
            button.layer.cornerRadius = 10;
            UILabel *label = PKLabel(15, PKTextColor(), NO);
            label.text = [_titles objectAtIndex:i];
            label.textAlignment = NSTextAlignmentCenter;
            label.frame = button.bounds;
            label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [button addSubview:label];
            PKAttachPressFeedback(button);
            [button addTarget:self action:@selector(choose:) forControlEvents:UIControlEventTouchUpInside];
            [_panel addSubview:button];
        }
        UIButton *cancel = [UIButton buttonWithType:UIButtonTypeCustom];
        cancel.tag = -1;
        [cancel setTitle:PKText(@"Отмена") forState:UIControlStateNormal];
        [cancel setTitleColor:PKAccentColor() forState:UIControlStateNormal];
        cancel.titleLabel.font = PKFont(PKFontWeightMedium, 16);
        PKAttachPressFeedback(cancel);
        [cancel addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
        [_panel addSubview:cancel];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = MIN(420.0f, self.bounds.size.width - 24.0f);
    NSUInteger rows = (_titles.count + 1) / 2;
    CGFloat height = 16 + rows * 48 + 48;
    PKPlaceView(_panel, CGRectMake((self.bounds.size.width - width) / 2, self.bounds.size.height - height - 12, width, height));
    CGFloat column = (width - 40) / 2;
    for (UIView *view in _panel.subviews) {
        NSInteger index = view.tag;
        if (index < 0) view.frame = CGRectMake(12, height - 48, width - 24, 44);
        else view.frame = CGRectMake(16 + (index % 2) * (column + 8), 12 + (index / 2) * 48, column, 40);
    }
}
- (void)presentInView:(UIView *)view {
    self.frame = view.bounds;
    [view addSubview:self];
    [self layoutIfNeeded];
    self.alpha = 0;
    _panel.transform = CGAffineTransformMakeTranslation(0, _panel.bounds.size.height + 40.0f);
    PKAnimatePopup(self, CGAffineTransformIdentity, 1, YES, nil);
    PKAnimatePopup(_panel, CGAffineTransformIdentity, 1, YES, nil);
}
- (void)dismiss {
    self.userInteractionEnabled = NO;
    PKAnimatePopup(self, CGAffineTransformIdentity, 0, NO, nil);
    PKAnimatePopup(_panel, CGAffineTransformMakeTranslation(0, _panel.bounds.size.height + 40.0f), 1, NO, ^(BOOL finished) {
        (void)finished;
        [self removeFromSuperview];
    });
}
- (void)cancel { [self dismiss]; }
- (void)choose:(UIButton *)button {
    NSInteger index = button.tag;
    [button.layer removeAllAnimations];
    void (^selection)(NSInteger) = [_selection copy];
    [self dismiss];
    if (selection) selection(index);
    [selection release];
}
- (void)dealloc { [_panel release]; [_titles release]; [_selection release]; [super dealloc]; }
@end

static const CGFloat kPad = 14.0f;
static const NSUInteger kMaxLinkRows = 8;

static UIFont *PKStoryBodyFont(void) { return PKFont(PKFontWeightRegular, 16.0f); }
static UIFont *PKStoryTitleFont(void) { return PKFont(PKFontWeightMedium, 20.0f); }
static UIFont *PKCommentBodyFont(void) { return PKFont(PKFontWeightRegular, 15.0f); }

static CGFloat PKWrappedHeight(NSString *text, UIFont *font, CGFloat width) {
    if (!text.length || width < 1.0f) return 0.0f;
    CGFloat height = PKEmojiTextHeight(text, font, width, 10000.0f);
    return MAX(ceilf(font.lineHeight), ceilf(height));
}

static NSString *PKLinkTitle(NSString *url) {
    NSRange scheme = [url rangeOfString:@"://"];
    NSString *title = scheme.location == NSNotFound ? url : [url substringFromIndex:scheme.location + 3];
    while ([title hasSuffix:@"/"] && title.length > 1) title = [title substringToIndex:title.length - 1];
    if (title.length > 46) title = [[title substringToIndex:45] stringByAppendingString:@"…"];
    return title;
}

#pragma mark - media block

@class PKStoryMediaCell;
@protocol PKStoryMediaCellDelegate <NSObject>
- (void)storyMediaCell:(PKStoryMediaCell *)cell didLoadURL:(NSString *)url size:(CGSize)size;
@end

@interface PKStoryMediaCell : UITableViewCell {
    UIImageView *_mediaView;
    UIImageView *_playBadge;
    UILabel *_loadLabel;
    UIActivityIndicatorView *_spinner;
    NSString *_representedURL;
    id<PKStoryMediaCellDelegate> _delegate;
}
- (void)setMedia:(NSDictionary *)media delegate:(id<PKStoryMediaCellDelegate>)delegate;
@end

@implementation PKStoryMediaCell
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.contentView.backgroundColor = [UIColor clearColor];
        _mediaView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _mediaView.contentMode = UIViewContentModeScaleAspectFit;
        _mediaView.clipsToBounds = YES;
        [self.contentView addSubview:_mediaView];
        _loadLabel = [PKLabel(13, PKMutedColor(), YES) retain];
        _loadLabel.textAlignment = NSTextAlignmentCenter;
        _loadLabel.numberOfLines = 0;
        _loadLabel.hidden = YES;
        [self.contentView addSubview:_loadLabel];
        _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:PKSpinnerStyle()];
        [self.contentView addSubview:_spinner];
        _playBadge = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 56, 56)];
        _playBadge.backgroundColor = [UIColor colorWithWhite:0 alpha:0.62f];
        _playBadge.layer.cornerRadius = 28.0f;
        _playBadge.contentMode = UIViewContentModeCenter;
        _playBadge.image = PKIcon(PKIconPlay, 28.0f, [UIColor whiteColor]);
        [self.contentView addSubview:_playBadge];
    }
    return self;
}
- (void)prepareForReuse {
    [super prepareForReuse];
    [self.contentView.layer removeAnimationForKey:@"pk.list.enter"];
    [_representedURL release];
    _representedURL = nil;
    _delegate = nil;
    _mediaView.image = nil;
    [_spinner stopAnimating];
    _loadLabel.hidden = YES;
}
- (void)setMedia:(NSDictionary *)media delegate:(id<PKStoryMediaCellDelegate>)delegate {
    _delegate = delegate;
    BOOL video = [[media objectForKey:@"type"] isEqualToString:@"video"];
    NSString *url = video ? [media objectForKey:@"poster"] : [media objectForKey:@"url"];
    [_representedURL release];
    _representedURL = [url copy];
    _mediaView.image = nil;
    _loadLabel.hidden = YES;
    _loadLabel.textColor = PKMutedColor();
    _playBadge.hidden = !video;
    self.backgroundColor = PKCardColor();
    _mediaView.backgroundColor = PKMediaWellColor();
    _spinner.activityIndicatorViewStyle = PKSpinnerStyle();
    if (url.length) {
        [_spinner startAnimating];
        NSString *requestedURL = [[url copy] autorelease];
        PKLoadImage(requestedURL, ^(UIImage *image) {
            if (![requestedURL isEqualToString:_representedURL]) return;
            [_spinner stopAnimating];
            _mediaView.image = image;
            _loadLabel.text = video ? PKText(@"Предпросмотр видео не загрузился. Само видео можно открыть.") : PKText(@"Изображение не загрузилось. Нажмите, чтобы повторить.");
            _loadLabel.hidden = image != nil;
            if (image && !video && image.size.width > 0 && image.size.height > 0) {
                CGSize size = image.size;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if ([requestedURL isEqualToString:_representedURL] &&
                        [_delegate respondsToSelector:@selector(storyMediaCell:didLoadURL:size:)])
                        [_delegate storyMediaCell:self didLoadURL:requestedURL size:size];
                });
            }
        });
    }
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.contentView.bounds;
    CGFloat side = PKContentSideInset(bounds.size.width);
    _mediaView.frame = CGRectMake(side, 0, bounds.size.width - 2 * side, bounds.size.height);
    _loadLabel.frame = CGRectMake(side + 18, floorf((bounds.size.height - 56) / 2), MAX(0, bounds.size.width - 2 * side - 36), 56);
    _spinner.center = CGPointMake(bounds.size.width / 2, bounds.size.height / 2);
    _playBadge.center = CGPointMake(bounds.size.width / 2, bounds.size.height / 2);
}
- (void)dealloc { [_mediaView release]; [_playBadge release]; [_loadLabel release]; [_spinner release]; [_representedURL release]; [super dealloc]; }
@end

#pragma mark - text block

/* a label, not a text view: the inset property is missing on ios 5 and 6 and the padding differs per
   release, so a text view cannot be measured */
@class PKStoryTextCell;
@protocol PKStoryTextCellDelegate <NSObject>
- (void)storyTextCell:(PKStoryTextCell *)cell didOpenMenuWithText:(NSString *)text links:(NSArray *)links;
@end

@interface PKStoryTextCell : UITableViewCell {
    UILabel *_body;
    UIButton *_links[8];
    NSArray *_urls;
    id<PKStoryTextCellDelegate> _delegate;
}
@property(nonatomic, assign) id<PKStoryTextCellDelegate> delegate;
- (void)setText:(NSString *)text links:(NSArray *)links;
@end

static CGFloat PKStoryTextHeight(NSString *text, NSArray *links, CGFloat tableWidth) {
    CGFloat side = PKContentSideInset(tableWidth);
    CGFloat height = 6.0f + PKWrappedHeight(text, PKStoryBodyFont(), tableWidth - side * 2.0f - kPad * 2.0f);
    NSUInteger rows = MIN(links.count, kMaxLinkRows);
    if (rows) height += 4.0f + rows * 30.0f;
    return height + 8.0f;
}

@implementation PKStoryTextCell
@synthesize delegate = _delegate;
- (void)pressed:(UILongPressGestureRecognizer *)press {
    if (press.state == UIGestureRecognizerStateBegan && _body.text.length && [_delegate respondsToSelector:@selector(storyTextCell:didOpenMenuWithText:links:)])
        [_delegate storyTextCell:self didOpenMenuWithText:_body.text links:_urls];
}
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
        NSUInteger index;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        _body = [[PKEmojiLabel alloc] initWithFrame:CGRectZero];
        _body.backgroundColor = [UIColor clearColor];
        _body.numberOfLines = 0;
        _body.font = PKStoryBodyFont();
        [self.contentView addSubview:_body];
        [self.contentView addGestureRecognizer:[[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(pressed:)] autorelease]];
        for (index = 0; index < kMaxLinkRows; index++) {
            UIButton *button = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
            button.titleLabel.font = PKFont(PKFontWeightMedium, 14.0f);
            button.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
            button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
            button.tag = (NSInteger)index;
            PKAttachPressFeedback(button);
            [button addTarget:self action:@selector(linkTapped:) forControlEvents:UIControlEventTouchUpInside];
            [self.contentView addSubview:button];
            _links[index] = button;
        }
    }
    return self;
}
- (void)prepareForReuse {
    [super prepareForReuse];
    [self.contentView.layer removeAnimationForKey:@"pk.list.enter"];
    _delegate = nil;
}
- (void)setText:(NSString *)text links:(NSArray *)links {
    NSUInteger index;
    self.backgroundColor = PKCardColor();
    _body.textColor = PKTextColor();
    _body.text = text;
    [_urls release];
    _urls = [links copy];
    for (index = 0; index < kMaxLinkRows; index++) {
        UIButton *button = _links[index];
        button.hidden = index >= _urls.count;
        if (index < _urls.count) {
            [button setTitle:PKLinkTitle([_urls objectAtIndex:index]) forState:UIControlStateNormal];
            [button setTitleColor:PKAccentColor() forState:UIControlStateNormal];
        }
    }
    [self setNeedsLayout];
}
- (void)linkTapped:(UIButton *)button {
    NSUInteger index = (NSUInteger)button.tag;
    if (index >= _urls.count) return;
    NSURL *url = [NSURL URLWithString:[_urls objectAtIndex:index]];
    if (url) [[UIApplication sharedApplication] openURL:url];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    NSUInteger index;
    CGFloat width = self.contentView.bounds.size.width;
    CGFloat side = PKContentSideInset(width);
    CGFloat textWidth = width - side * 2.0f - kPad * 2.0f;
    CGFloat height = PKWrappedHeight(_body.text, PKStoryBodyFont(), textWidth);
    CGFloat y = 6.0f;
    _body.frame = CGRectMake(side + kPad, y, textWidth, height);
    y += height + 4.0f;
    for (index = 0; index < MIN(_urls.count, kMaxLinkRows); index++) {
        _links[index].frame = CGRectMake(side + kPad, y, textWidth, 30.0f);
        y += 30.0f;
    }
}
- (void)dealloc {
    NSUInteger index;
    for (index = 0; index < kMaxLinkRows; index++) [_links[index] release];
    [_body release]; [_urls release];
    [super dealloc];
}
@end

#pragma mark - comment

static const CGFloat kCommentStep = 14.0f;
static const CGFloat kCommentFooter = 32.0f;
static const CGFloat kCommentBar = 44.0f;

static CGFloat PKCommentLineX(CGFloat side, NSInteger level) {
    return side + 12.0f + (CGFloat)(level - 1) * kCommentStep + 2.0f;
}

static const CGFloat kCommentAvatar = 28.0f;

typedef struct {
    CGRect avatar;
    CGRect author;
    CGRect menu;
    CGRect replyTo;
    CGRect quote;
    CGRect body;
    CGRect media;
    CGRect reactions;
    CGRect reply;
    CGRect up;
    CGRect score;
    CGRect down;
    CGRect bar;
    CGRect collapse;
    CGRect separator;
    BOOL showBar;
    CGFloat height;
} PKCommentLayout;

static UIFont *PKCommentQuoteFont(void) { return PKFont(PKFontWeightRegular, 13.0f); }

/* quote is the parent's text while the replyTo line is open */
static PKCommentLayout PKLayoutComment(PKComment *comment, CGFloat tableWidth, BOOL showBar, BOOL hasReplyTo, NSString *quote) {
    PKCommentLayout layout;
    memset(&layout, 0, sizeof(layout));
    NSInteger depth = MIN(7, MAX(0, comment.indent));
    CGFloat side = PKContentSideInset(tableWidth);
    CGFloat left = side + 12.0f + (CGFloat)depth * kCommentStep + (depth > 0 ? 6.0f : 0.0f);
    CGFloat right = tableWidth - side - 12.0f;
    CGFloat width = MAX(100.0f, right - left);
    CGFloat y = 10.0f;

    layout.menu = CGRectMake(right - 30.0f, 4.0f, 30.0f, 30.0f);
    layout.avatar = CGRectMake(left, y, kCommentAvatar, kCommentAvatar);
    layout.author = CGRectMake(left + kCommentAvatar + 8.0f, y + 5.0f, MAX(40.0f, width - kCommentAvatar - 8.0f - 34.0f), 18.0f);
    y += kCommentAvatar + 2.0f;
    if (hasReplyTo) {
        layout.replyTo = CGRectMake(left, y, width, 20.0f);
        y += 20.0f;
        if (quote.length) {
            CGFloat line = ceilf(PKCommentQuoteFont().lineHeight);
            CGFloat quoteHeight = MIN(PKWrappedHeight(quote, PKCommentQuoteFont(), width - 12.0f), line * 3.0f);
            layout.quote = CGRectMake(left + 12.0f, y + 2.0f, width - 12.0f, quoteHeight);
            y += quoteHeight + 6.0f;
        }
    }
    if (comment.body.length) {
        CGFloat height = PKWrappedHeight(comment.body, PKCommentBodyFont(), width);
        y += 8.0f;
        layout.body = CGRectMake(left, y, width, height);
        y += height;
    }
    if (comment.mediaURL.length) {
        CGFloat height = comment.mediaIsSticker ? 132.0f : (CGFloat)pk_media_height(width, comment.mediaWidth, comment.mediaHeight);
        if (height <= 0) height = 198.0f;
        height = MAX(1.0f, ceilf(height));
        y += 8.0f;
        layout.media = CGRectMake(left, y, width, height);
        y += height;
    }
    if (comment.reactions.count) {
        y += 8.0f;
        layout.reactions = CGRectMake(left, y, width, 20.0f);
        y += 20.0f;
    }
    y += 4.0f;
    layout.reply = CGRectMake(left, y, 96.0f, kCommentFooter);
    layout.down = CGRectMake(right - 32.0f, y, 32.0f, kCommentFooter);
    layout.score = CGRectMake(right - 32.0f - 54.0f, y, 54.0f, kCommentFooter);
    layout.up = CGRectMake(right - 32.0f - 54.0f - 32.0f, y, 32.0f, kCommentFooter);
    y += kCommentFooter;
    if (showBar) {
        y += 4.0f;
        layout.showBar = YES;
        layout.bar = CGRectMake(left, y, width, kCommentBar);
        y += kCommentBar;
    }
    y += 8.0f;
    layout.height = MAX(56.0f, y);
    if (depth > 0) layout.collapse = CGRectMake(PKCommentLineX(side, depth) - 11.0f, 8.0f, 22.0f, 22.0f);
    layout.separator = CGRectMake(left, layout.height - 1.0f, right - left, 1.0f);
    return layout;
}

/* 400 comments mean 400 text heights on every reload and fold, seconds on a 4S. a height depends only on
   the comment, the width and the branch bar, so it is cached */
static CGFloat PKCommentRowHeight(PKComment *comment, CGFloat tableWidth, BOOL showBar, BOOL hasReplyTo, NSString *quote) {
    static NSMutableDictionary *heights;
    static const NSUInteger kLimit = 1200;
    NSString *key = nil;
    if (comment.commentID.length) key = [NSString stringWithFormat:@"%@|%.0f|%.0f:%.0f|%d|%d|%lu", comment.commentID, tableWidth, comment.mediaWidth, comment.mediaHeight, showBar ? 1 : 0, hasReplyTo ? 1 : 0, (unsigned long)quote.length];
    if (!heights) heights = [[NSMutableDictionary alloc] init];
    NSNumber *cached = key ? [heights objectForKey:key] : nil;
    if (cached) return [cached floatValue];
    CGFloat height = PKLayoutComment(comment, tableWidth, showBar, hasReplyTo, quote).height;
    if (key) {
        if (heights.count >= kLimit) [heights removeAllObjects];
        [heights setObject:[NSNumber numberWithFloat:(float)height] forKey:key];
    }
    return height;
}

/* one pass, a view per line would add eight subviews to every comment row */
@interface PKThreadLines : UIView {
    NSInteger _depth;
    CGFloat _side;
}
- (void)setDepth:(NSInteger)depth side:(CGFloat)side;
@end

@implementation PKThreadLines
- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
        self.backgroundColor = [UIColor clearColor];
    }
    return self;
}
- (void)setDepth:(NSInteger)depth side:(CGFloat)side {
    _depth = depth;
    _side = side;
    [self setNeedsDisplay];
}
- (void)drawRect:(CGRect)rect {
    (void)rect;
    NSInteger level;
    [[PKMutedColor() colorWithAlphaComponent:0.45f] set];
    for (level = 1; level <= _depth; level++)
        UIRectFill(CGRectMake(PKCommentLineX(_side, level), 0.0f, 1.5f, self.bounds.size.height));
}
@end

@class PKCommentCell;
@protocol PKCommentCellDelegate <NSObject>
- (void)commentCellDidToggleBranch:(PKCommentCell *)cell;
- (void)commentCellDidOpenMedia:(PKCommentCell *)cell;
- (void)commentCellDidLoadImage:(PKCommentCell *)cell;
@optional
- (void)commentCell:(PKCommentCell *)cell didOpenAuthor:(NSString *)author;
/* the id is the comment whose replies fold */
- (void)commentCell:(PKCommentCell *)cell didFoldBranchOfID:(NSString *)identifier;
- (void)commentCellDidReply:(PKCommentCell *)cell;
- (void)commentCell:(PKCommentCell *)cell didVote:(NSInteger)vote;
- (void)commentCellDidOpenMenu:(PKCommentCell *)cell;
- (void)commentCellDidToggleQuote:(PKCommentCell *)cell;
@end

@interface PKCommentCell : UITableViewCell {
    PKThreadLines *_lines;
    UIView *_separator;
    UIImageView *_avatar;
    UIButton *_replyToButton;
    UILabel *_quote;
    NSString *_replyToAuthor;
    NSString *_quoteText;
    NSString *_representedAvatarURL;
    UILabel *_author;
    UIButton *_authorButton;
    UILabel *_date;
    UILabel *_body;
    UILabel *_reactions;
    UIImageView *_mediaView;
    UIButton *_menuButton;
    UIButton *_replyButton;
    UIButton *_upButton;
    UIButton *_downButton;
    UILabel *_score;
    UIButton *_barButton;
    UILabel *_barLabel;
    UIImageView *_barIcon;
    UIButton *_collapseButton;
    NSString *_representedURL;
    NSString *_collapseOwnerID;
    PKComment *_comment;
    id<PKCommentCellDelegate> _delegate;
    NSInteger _depth;
    NSInteger _hiddenReplies;
    BOOL _showBar;
}
@property(nonatomic, readonly) PKComment *comment;
/* foldOwnerID is the first reply of a long branch, whose line carries the fold button. hiddenReplies is 0
   when the branch is open */
- (void)setComment:(PKComment *)comment hiddenReplies:(NSInteger)hiddenReplies foldOwnerID:(NSString *)foldOwnerID
           replyToAuthor:(NSString *)replyToAuthor quote:(NSString *)quote delegate:(id<PKCommentCellDelegate>)delegate;
@end

@implementation PKCommentCell
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.contentView.backgroundColor = [UIColor clearColor];
        _lines = [[PKThreadLines alloc] initWithFrame:CGRectZero];
        [self.contentView addSubview:_lines];
        _separator = [[UIView alloc] initWithFrame:CGRectZero];
        [self.contentView addSubview:_separator];
        _avatar = [[UIImageView alloc] initWithFrame:CGRectZero];
        _avatar.contentMode = UIViewContentModeScaleAspectFill;
        _avatar.clipsToBounds = YES;
        _avatar.layer.cornerRadius = kCommentAvatar / 2.0f;
        [self.contentView addSubview:_avatar];
        _replyToButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _replyToButton.titleLabel.font = PKFont(PKFontWeightMedium, 13.0f);
        _replyToButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _replyToButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        PKAttachPressFeedback(_replyToButton);
        [_replyToButton addTarget:self action:@selector(quoteTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_replyToButton];
        _quote = [PKLabel(13, PKMutedColor(), NO) retain];
        _quote.font = PKCommentQuoteFont();
        _quote.numberOfLines = 3;
        [self.contentView addSubview:_quote];
        _author = [PKLabel(14, PKTextColor(), YES) retain]; [self.contentView addSubview:_author];
        _authorButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _authorButton.accessibilityLabel = PKText(@"Профиль автора");
        [_authorButton addTarget:self action:@selector(authorTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_authorButton];
        _date = [PKLabel(12, PKMutedColor(), NO) retain]; [self.contentView addSubview:_date];
        _body = [[PKEmojiLabel alloc] initWithFrame:CGRectZero];
        _body.backgroundColor = [UIColor clearColor];
        _body.font = PKCommentBodyFont();
        _body.numberOfLines = 0;
        [self.contentView addSubview:_body];
        _reactions = [PKLabel(13, PKMutedColor(), NO) retain]; [self.contentView addSubview:_reactions];
        _mediaView = [[UIImageView alloc] initWithFrame:CGRectZero];
        _mediaView.contentMode = UIViewContentModeScaleAspectFit;
        _mediaView.clipsToBounds = YES;
        _mediaView.layer.cornerRadius = 8.0f;
        _mediaView.userInteractionEnabled = YES;
        [_mediaView addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(mediaTapped)] autorelease]];
        [self.contentView addSubview:_mediaView];

        _menuButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _menuButton.titleLabel.font = PKFont(PKFontWeightBold, 20.0f);
        _menuButton.accessibilityLabel = PKText(@"Действия");
        [_menuButton setTitle:@"⋮" forState:UIControlStateNormal];
        PKAttachPressFeedback(_menuButton);
        [_menuButton addTarget:self action:@selector(menuTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_menuButton];
        _replyButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _replyButton.titleLabel.font = PKFont(PKFontWeightMedium, 13.0f);
        _replyButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        [_replyButton setTitle:PKText(@"ОТВЕТИТЬ") forState:UIControlStateNormal];
        PKAttachPressFeedback(_replyButton);
        [_replyButton addTarget:self action:@selector(replyTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_replyButton];
        _upButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _upButton.accessibilityLabel = PKText(@"Плюс");
        PKAttachPressFeedback(_upButton);
        [_upButton addTarget:self action:@selector(upTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_upButton];
        _downButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _downButton.accessibilityLabel = PKText(@"Минус");
        PKAttachPressFeedback(_downButton);
        [_downButton addTarget:self action:@selector(downTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_downButton];
        _score = [PKLabel(13, PKMutedColor(), YES) retain]; _score.textAlignment = NSTextAlignmentCenter;
        [self.contentView addSubview:_score];

        /* as large as a post button, so nobody hunts for a small sign */
        _barButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _barButton.layer.cornerRadius = 8.0f;
        PKAttachPressFeedback(_barButton);
        [_barButton addTarget:self action:@selector(barTapped) forControlEvents:UIControlEventTouchUpInside];
        _barLabel = [PKLabel(13, PKMutedColor(), YES) retain];
        _barLabel.userInteractionEnabled = NO;
        [_barButton addSubview:_barLabel];
        _barIcon = [[UIImageView alloc] initWithFrame:CGRectZero];
        _barIcon.contentMode = UIViewContentModeCenter;
        _barIcon.userInteractionEnabled = NO;
        [_barButton addSubview:_barIcon];
        [self.contentView addSubview:_barButton];
        _collapseButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _collapseButton.titleLabel.font = PKFont(PKFontWeightBold, 18.0f);
        _collapseButton.layer.cornerRadius = 6.0f;
        _collapseButton.layer.borderWidth = 1.0f;
        _collapseButton.accessibilityLabel = PKText(@"Свернуть ветвь");
        [_collapseButton setTitle:@"−" forState:UIControlStateNormal];
        PKAttachPressFeedback(_collapseButton);
        [_collapseButton addTarget:self action:@selector(collapseTapped) forControlEvents:UIControlEventTouchUpInside];
        [self.contentView addSubview:_collapseButton];

        UILongPressGestureRecognizer *press = [[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(pressed:)] autorelease];
        [self.contentView addGestureRecognizer:press];
    }
    return self;
}
- (void)prepareForReuse {
    [super prepareForReuse];
    [_representedURL release]; _representedURL = nil;
    [_collapseOwnerID release]; _collapseOwnerID = nil;
    [_representedAvatarURL release]; _representedAvatarURL = nil;
    [_replyToAuthor release]; _replyToAuthor = nil;
    [_quoteText release]; _quoteText = nil;
    _avatar.image = nil;
    [_comment release]; _comment = nil;
    _delegate = nil;
    [_collapseButton.layer removeAnimationForKey:@"pk.bounce"];
    [_mediaView stopAnimating]; _mediaView.image = nil;
}
- (PKComment *)comment { return _comment; }
- (void)setComment:(PKComment *)comment hiddenReplies:(NSInteger)hiddenReplies foldOwnerID:(NSString *)foldOwnerID
           replyToAuthor:(NSString *)replyToAuthor quote:(NSString *)quote delegate:(id<PKCommentCellDelegate>)delegate {
    UIColor *muted = PKMutedColor();
    [_comment release]; _comment = [comment retain];
    _delegate = delegate;
    _depth = MIN(7, MAX(0, comment.indent));
    _hiddenReplies = hiddenReplies;
    _showBar = hiddenReplies > 0;
    [_collapseOwnerID release]; _collapseOwnerID = [foldOwnerID copy];
    [_replyToAuthor release]; _replyToAuthor = [replyToAuthor copy];
    [_quoteText release]; _quoteText = [quote copy];
    self.backgroundColor = PKCardColor();
    _avatar.backgroundColor = PKControlColor();
    _avatar.image = nil;
    [_representedAvatarURL release]; _representedAvatarURL = [comment.avatarURL copy];
    if (_representedAvatarURL.length) {
        NSString *requestedAvatar = [[_representedAvatarURL copy] autorelease];
        PKLoadImage(requestedAvatar, ^(UIImage *image) {
            if ([requestedAvatar isEqualToString:_representedAvatarURL]) _avatar.image = image;
        });
    }
    _replyToButton.hidden = !_replyToAuthor.length;
    [_replyToButton setTitle:[NSString stringWithFormat:PKText(@"Ответ на %@  %@"), _replyToAuthor ?: @"", _quoteText.length ? @"▴" : @"▾"] forState:UIControlStateNormal];
    [_replyToButton setTitleColor:PKMutedColor() forState:UIControlStateNormal];
    _quote.hidden = !_quoteText.length;
    _quote.text = _quoteText;
    _quote.textColor = PKMutedColor();
    _author.text = comment.author;
    _author.textColor = PKTextColor();
    _date.text = comment.date;
    _date.textColor = muted;
    _body.text = comment.body;
    _body.textColor = PKTextColor();
    _reactions.text = PKReactionSummary(comment.reactions, 5);
    _reactions.textColor = muted;
    _date.hidden = !comment.date.length;
    _body.hidden = !comment.body.length;
    _reactions.hidden = !comment.reactions.count;
    [_menuButton setTitleColor:muted forState:UIControlStateNormal];
    [_replyButton setTitleColor:PKAccentColor() forState:UIControlStateNormal];
    [_upButton setImage:PKIcon(PKIconArrowUp, 18.0f, muted) forState:UIControlStateNormal];
    [_downButton setImage:PKIcon(PKIconArrowDown, 18.0f, muted) forState:UIControlStateNormal];
    _score.text = !comment.scoreKnown ? @"…" : (comment.score > 0 ? [NSString stringWithFormat:@"+%@", PKCompactScore(comment.score)] : PKCompactScore(comment.score));
    _score.textColor = comment.score > 0 ? PKAccentColor() : (comment.score < 0 ? PKDangerColor() : muted);
    _barButton.hidden = !_showBar;
    _barButton.backgroundColor = PKControlColor();
    _barLabel.text = [NSString stringWithFormat:PKText(@"РАСКРЫТЬ ВЕТВЬ: %ld"), (long)hiddenReplies];
    _barLabel.textColor = muted;
    _barIcon.image = PKIcon(PKIconComment, 22.0f, muted);
    _collapseButton.hidden = !_collapseOwnerID.length || _depth < 1;
    _collapseButton.backgroundColor = PKCardColor();
    _collapseButton.layer.borderColor = [muted colorWithAlphaComponent:0.5f].CGColor;
    [_collapseButton setTitleColor:muted forState:UIControlStateNormal];
    _separator.backgroundColor = PKSeparatorColor();
    _mediaView.backgroundColor = comment.mediaIsSticker ? [UIColor clearColor] : PKMediaWellColor();
    [_representedURL release]; _representedURL = [comment.mediaURL copy];
    [_mediaView stopAnimating]; _mediaView.image = nil; _mediaView.hidden = !_representedURL.length;
    if (_representedURL.length) {
        NSString *requestedURL = [[_representedURL copy] autorelease];
        PKLoadImage(requestedURL, ^(UIImage *image) {
            if (![requestedURL isEqualToString:_representedURL]) return;
            _mediaView.image = image;
            if (image.images.count > 1) [_mediaView startAnimating];
            if (image && !comment.mediaIsSticker && image.size.width > 0 && image.size.height > 0 &&
                (comment.mediaWidth != image.size.width || comment.mediaHeight != image.size.height)) {
                comment.mediaWidth = image.size.width;
                comment.mediaHeight = image.size.height;
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (_comment == comment && [requestedURL isEqualToString:_representedURL] &&
                        [_delegate respondsToSelector:@selector(commentCellDidLoadImage:)])
                        [_delegate commentCellDidLoadImage:self];
                });
            }
        });
    }
    [self setNeedsLayout];
}
- (void)quoteTapped { if ([_delegate respondsToSelector:@selector(commentCellDidToggleQuote:)]) [_delegate commentCellDidToggleQuote:self]; }
- (void)barTapped { if ([_delegate respondsToSelector:@selector(commentCellDidToggleBranch:)]) [_delegate commentCellDidToggleBranch:self]; }
- (void)collapseTapped {
    if (_collapseOwnerID.length && [_delegate respondsToSelector:@selector(commentCell:didFoldBranchOfID:)])
        [_delegate commentCell:self didFoldBranchOfID:_collapseOwnerID];
}
- (void)replyTapped { if ([_delegate respondsToSelector:@selector(commentCellDidReply:)]) [_delegate commentCellDidReply:self]; }
- (void)upTapped { if ([_delegate respondsToSelector:@selector(commentCell:didVote:)]) [_delegate commentCell:self didVote:1]; }
- (void)downTapped { if ([_delegate respondsToSelector:@selector(commentCell:didVote:)]) [_delegate commentCell:self didVote:-1]; }
- (void)menuTapped { if ([_delegate respondsToSelector:@selector(commentCellDidOpenMenu:)]) [_delegate commentCellDidOpenMenu:self]; }
- (void)pressed:(UILongPressGestureRecognizer *)press {
    if (press.state == UIGestureRecognizerStateBegan) [self menuTapped];
}
- (void)authorTapped {
    if (_comment.author.length && [_delegate respondsToSelector:@selector(commentCell:didOpenAuthor:)])
        [_delegate commentCell:self didOpenAuthor:_comment.author];
}
- (void)mediaTapped { PKAnimatePress(_mediaView); if ([_delegate respondsToSelector:@selector(commentCellDidOpenMedia:)]) [_delegate commentCellDidOpenMedia:self]; }
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width;
    PKCommentLayout layout = PKLayoutComment(_comment, width, _showBar, _replyToAuthor.length > 0, _quoteText);
    _lines.frame = self.contentView.bounds;
    [_lines setDepth:_depth side:PKContentSideInset(width)];
    _separator.frame = layout.separator;
    CGFloat nameWidth = MIN(layout.author.size.width, ceilf([_author sizeThatFits:CGSizeMake(layout.author.size.width, layout.author.size.height)].width) + 4.0f);
    _avatar.frame = layout.avatar;
    _replyToButton.frame = layout.replyTo;
    _quote.frame = layout.quote;
    _author.frame = CGRectMake(layout.author.origin.x, layout.author.origin.y, nameWidth, layout.author.size.height);
    _date.frame = CGRectMake(layout.author.origin.x + nameWidth + 6.0f, layout.author.origin.y + 1.0f,
                             MAX(0.0f, layout.author.size.width - nameWidth - 6.0f), layout.author.size.height);
    _authorButton.frame = CGRectMake(layout.author.origin.x, layout.author.origin.y - 6.0f, nameWidth + 8.0f, layout.author.size.height + 12.0f);
    _menuButton.frame = layout.menu;
    _body.frame = layout.body;
    _mediaView.frame = layout.media;
    _reactions.frame = layout.reactions;
    _replyButton.frame = layout.reply;
    _upButton.frame = layout.up;
    _score.frame = layout.score;
    _downButton.frame = layout.down;
    _barButton.frame = layout.bar;
    _barLabel.frame = CGRectMake(16.0f, 0.0f, MAX(0.0f, layout.bar.size.width - 64.0f), layout.bar.size.height);
    _barIcon.frame = CGRectMake(layout.bar.size.width - 48.0f, 0.0f, 36.0f, layout.bar.size.height);
    _collapseButton.frame = layout.collapse;
}
- (void)dealloc {
    [_lines release]; [_separator release]; [_avatar release]; [_replyToButton release]; [_quote release]; [_replyToAuthor release]; [_quoteText release]; [_representedAvatarURL release]; [_author release]; [_authorButton release]; [_date release]; [_body release];
    [_reactions release]; [_mediaView release]; [_menuButton release]; [_replyButton release]; [_upButton release]; [_downButton release];
    [_score release]; [_barButton release]; [_barLabel release]; [_barIcon release]; [_collapseButton release];
    [_representedURL release]; [_collapseOwnerID release]; [_comment release];
    [super dealloc];
}
@end

#pragma mark - screen

@interface StoryViewController () <UITableViewDataSource, UITableViewDelegate, PKCommentCellDelegate, PKStoryMediaCellDelegate, PKStoryTextCellDelegate> {
    PKPost *_post;
    NSString *_storyHTML;
    UITableView *_table;
    NSMutableArray *_comments;
    NSMutableArray *_visibleComments;
    NSMutableSet *_collapsedCommentIDs;
    /* feeds the folded-branch bar and picks the branches long enough for a fold button */
    NSMutableDictionary *_descendants;
    NSMutableDictionary *_commentsByID;
    NSMutableSet *_openQuoteIDs;
    NSString *_focusCommentID;
    NSString *_markedCommentID;
    UIButton *_composeButton;
    BOOL _commentsLoadedOnce;
    UILabel *_toast;
    UIView *_actions;
    NSArray *_blocks;
    NSMutableDictionary *_mediaDimensions;
    NSArray *_storyReactions;
    UIActivityIndicatorView *_spinner;
    NSString *_commentsNote;
    BOOL _loadingStory;
    CGFloat _layoutWidth;
    NSUInteger _requestGeneration;
    /* runs once after the next reload, to compare with what a reaction request meant to do */
    void (^_afterLoad)(void);
}
@end

@implementation StoryViewController
- (id)initWithPost:(PKPost *)post { return [self initWithPost:post focusCommentID:nil]; }
- (id)initWithPost:(PKPost *)post focusCommentID:(NSString *)commentID {
    if ((self = [super init])) {
        _post = [post retain];
        _focusCommentID = [commentID copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = PKText(@"Публикация");
    self.view.backgroundColor = PKBackgroundColor();
    _mediaDimensions = [[NSMutableDictionary alloc] init];
    _comments = [[NSMutableArray alloc] init];
    _visibleComments = [[NSMutableArray alloc] init];
    _collapsedCommentIDs = [[NSMutableSet alloc] init];
    _descendants = [[NSMutableDictionary alloc] init];
    _commentsByID = [[NSMutableDictionary alloc] init];
    _openQuoteIDs = [[NSMutableSet alloc] init];
    _table = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _table.dataSource = self;
    _table.delegate = self;
    PKStyleTable(_table);
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    [self.view addSubview:_table];
    self.navigationItem.rightBarButtonItem = PKIconBarItem(PKIconShare, PKText(@"Поделиться"), self, @selector(shareStory));

    _toast = [[PKEmojiLabel alloc] initWithFrame:CGRectZero];
    _toast.font = PKFont(PKFontWeightMedium, 13.0f);
    _toast.textColor = [UIColor whiteColor];
    _toast.backgroundColor = [UIColor colorWithWhite:0.1f alpha:0.88f];
    _toast.textAlignment = NSTextAlignmentCenter;
    _toast.numberOfLines = 2;
    _toast.layer.cornerRadius = 12.0f;
    _toast.clipsToBounds = YES;
    _toast.alpha = 0.0f;
    [self.view addSubview:_toast];

    _composeButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    _composeButton.frame = CGRectMake(0, 0, 56, 56);
    _composeButton.layer.cornerRadius = 28.0f;
    _composeButton.layer.shadowColor = [UIColor blackColor].CGColor;
    _composeButton.layer.shadowOpacity = 0.3f;
    _composeButton.layer.shadowRadius = 4.0f;
    _composeButton.layer.shadowOffset = CGSizeMake(0, 2);
    _composeButton.backgroundColor = PKAccentColor();
    _composeButton.accessibilityLabel = PKText(@"Написать комментарий");
    [_composeButton setImage:PKIcon(PKIconComment, 26.0f, [UIColor whiteColor]) forState:UIControlStateNormal];
    PKAttachPressFeedback(_composeButton);
    [_composeButton addTarget:self action:@selector(composeTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:_composeButton];

    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:PKSpinnerStyle()];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged) name:PKThemeDidChangeNotification object:nil];
    _loadingStory = YES;
    [_spinner startAnimating];
    [self updateHeader];
    [self loadStory];
}

- (void)loadStory {
    NSUInteger generation = ++_requestGeneration;
    PKLoadStory(_post, ^(NSString *html, NSError *error) {
        if (generation != _requestGeneration) return;
        _loadingStory = NO;
        [_spinner stopAnimating];
        if (!html) {
            [_afterLoad release]; _afterLoad = nil;
            [self updateHeader];
            [self showToast:[NSString stringWithFormat:PKText(@"Не удалось открыть публикацию: %@"), error.localizedDescription ?: PKText(@"нет ответа сервера")]];
            return;
        }
        BOOL firstLoad = _storyHTML == nil;
        [_storyHTML release];
        _storyHTML = [html retain];
        [_blocks release];
        _blocks = [PKStoryBlocksFromHTML(html) retain];
        /* the page reserves each picture's box, so the row keeps its height when the picture arrives */
        for (NSDictionary *block in _blocks) {
            NSString *blockURL = [block objectForKey:@"url"];
            CGFloat blockWidth = (CGFloat)[[block objectForKey:@"width"] longValue], blockHeight = (CGFloat)[[block objectForKey:@"height"] longValue];
            if ([[block objectForKey:@"type"] isEqualToString:@"image"] && blockURL.length && blockWidth > 0 && blockHeight > 0 && ![_mediaDimensions objectForKey:blockURL])
                [_mediaDimensions setObject:[NSValue valueWithCGSize:CGSizeMake(blockWidth, blockHeight)] forKey:blockURL];
        }
        NSInteger score = 0;
        if (PKStoryScoreFromHTML(html, &score)) {
            _post.score = score;
            _post.scoreKnown = YES;
        }
        [_storyReactions release]; _storyReactions = [PKStoryReactionsFromHTML(html) retain];
        [_commentsNote release]; _commentsNote = [PKText(@"Загружаем комментарии…") copy];
        [self updateHeader];
        [self rebuildActions];
        [_table reloadData];
        if (firstLoad) PKAnimateListAppearance(_table);
        PKLoadComments(_post, html, ^(NSArray *comments, NSError *commentsError) {
            if (generation != _requestGeneration) return;
            [_commentsNote release]; _commentsNote = nil;
            if (commentsError) {
                _commentsNote = [[NSString stringWithFormat:PKText(@"Комментарии не загрузились: %@"), commentsError.localizedDescription] copy];
            } else if (!comments.count) {
                _commentsNote = [PKText(@"Комментариев пока нет") copy];
            }
            [_comments removeAllObjects];
            [_comments addObjectsFromArray:comments];
            [self rebuildDescendants];
            if (!_commentsLoadedOnce && !commentsError) {
                _commentsLoadedOnce = YES;
                [_collapsedCommentIDs removeAllObjects];
                if (PKCollapseCommentBranchesEnabled()) {
                    for (PKComment *comment in _comments)
                        if (comment.commentID.length && [self commentHasChildren:comment]) [_collapsedCommentIDs addObject:comment.commentID];
                }
            }
            [self unfoldAncestorsOfFocusedComment];
            [self rebuildVisibleComments];
            [self rebuildActions];
            [_table reloadData];
            if (!commentsError) [self scrollToFocusedComment];
            [self runAfterLoad];
            if (!commentsError) {
                PKLoadHiddenCommentScores(_post, _comments, ^(NSDictionary *scores, BOOL finished, NSError *scoreError) {
                    if (generation != _requestGeneration) return;
                    for (PKComment *comment in _comments) {
                        NSNumber *score = [scores objectForKey:comment.commentID];
                        if (!score || !comment.scoreHidden) continue;
                        comment.score = [score integerValue];
                        comment.scoreKnown = YES;
                        comment.scoreHidden = NO;
                    }
                    if (finished && scoreError) {
                        NSLog(@"Weeabu comment ratings: %@", scoreError);
                        [_commentsNote release];
                        _commentsNote = [PKText(@"Некоторые рейтинги комментариев недоступны") copy];
                        [self rebuildActions];
                    }
                    [_table reloadData];
                });
            }
        });
    });
}

- (void)runAfterLoad {
    void (^block)(void) = _afterLoad;
    _afterLoad = nil;
    if (block) { block(); [block release]; }
}

- (NSArray *)reactionsOfCommentID:(NSString *)identifier {
    for (PKComment *item in _comments) if ([item.commentID isEqualToString:identifier]) return item.reactions;
    return nil;
}

- (void)themeChanged {
    self.view.backgroundColor = PKBackgroundColor();
    PKStyleTable(_table);
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _spinner.activityIndicatorViewStyle = PKSpinnerStyle();
    _composeButton.backgroundColor = PKAccentColor();
    [self updateHeader];
    [self rebuildActions];
    [_table reloadData];
}

/* heights come from the table width, so a turn rebuilds the header and asks every row again */
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = _table.bounds.size.width;
    _toast.frame = CGRectMake(24.0f, self.view.bounds.size.height - 70.0f, self.view.bounds.size.width - 48.0f, 40.0f);
    _composeButton.frame = CGRectMake(self.view.bounds.size.width - PKContentSideInset(self.view.bounds.size.width) - 72.0f,
                                      self.view.bounds.size.height - 76.0f, 56.0f, 56.0f);
    [self.view bringSubviewToFront:_composeButton];
    if (width == _layoutWidth) return;
    _layoutWidth = width;
    [self updateHeader];
    [self rebuildActions];
    [_table reloadData];
}

- (void)showToast:(NSString *)text {
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideToast) object:nil];
    _toast.text = text;
    [self.view bringSubviewToFront:_toast];
    BOOL appearing = _toast.alpha < 0.5f;
    [UIView animateWithDuration:PKMotionDuration(0.18) animations:^{ _toast.alpha = 1.0f; }];
    if (appearing) PKAnimateSpring(_toast, CGAffineTransformConcat(CGAffineTransformMakeScale(0.92f, 0.92f), CGAffineTransformMakeTranslation(0, 12)), 1.0f, PK_SPRING_SPATIAL_FAST, 0, @"pk.toast");
    [self performSelector:@selector(hideToast) withObject:nil afterDelay:3.0];
}

- (void)hideToast {
    [UIView animateWithDuration:PKMotionDuration(0.25) animations:^{ _toast.alpha = 0.0f; }];
}

#pragma mark header

- (void)updateHeader {
    CGFloat width = _table.bounds.size.width > 0 ? _table.bounds.size.width : self.view.bounds.size.width;
    CGFloat side = PKContentSideInset(width);
    CGFloat textWidth = width - side * 2.0f - kPad * 2.0f;
    CGFloat titleHeight = PKWrappedHeight(_post.title, PKStoryTitleFont(), textWidth);
    CGFloat parentRow = _post.parentURL.length ? 34.0f : 0.0f;
    UIView *header = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 64.0f + titleHeight + 6.0f + parentRow)] autorelease];
    header.backgroundColor = PKCardColor();

    UIImageView *avatar = [[[UIImageView alloc] initWithFrame:CGRectMake(side + kPad, 14.0f, 36.0f, 36.0f)] autorelease];
    avatar.contentMode = UIViewContentModeScaleAspectFill;
    avatar.clipsToBounds = YES;
    avatar.layer.cornerRadius = 18.0f;
    avatar.backgroundColor = PKControlColor();
    [header addSubview:avatar];
    if (_post.avatarURL.length) {
/* a slow load may finish after rotation dropped the view, the block keeps it alive */
        [avatar retain];
        PKLoadImage(_post.avatarURL, ^(UIImage *image) {
            avatar.image = image;
            [avatar release];
        });
    }
    CGFloat textX = side + kPad + 36.0f + 10.0f;
    UILabel *name = PKLabel(15, PKTextColor(), YES);
    name.text = _post.author.length ? _post.author : @"Weeabu";
    name.frame = CGRectMake(textX, 14.0f, width - textX - side - kPad, 19.0f);
    [header addSubview:name];
    UILabel *sub = PKLabel(12, PKMutedColor(), NO);
    NSMutableArray *parts = [NSMutableArray array];
    if (_post.community.length) [parts addObject:_post.community];
    if (_post.date.length) [parts addObject:_post.date];
    sub.text = [parts componentsJoinedByString:@"  ·  "];
    sub.frame = CGRectMake(textX, 33.0f, width - textX - side - kPad, 16.0f);
    [header addSubview:sub];
    if (_post.author.length) {
        UIButton *author = [UIButton buttonWithType:UIButtonTypeCustom];
        author.frame = CGRectMake(side + kPad - 4.0f, 10.0f, textX - side - kPad + MIN(220.0f, name.frame.size.width), 44.0f);
        author.accessibilityLabel = PKText(@"Профиль автора");
        [author addTarget:self action:@selector(openAuthorProfile) forControlEvents:UIControlEventTouchUpInside];
        [header addSubview:author];
    }
    if (_loadingStory) {
        _spinner.center = CGPointMake(width - side - kPad - 10.0f, 32.0f);
        [header addSubview:_spinner];
    }

    UILabel *title = [[[PKEmojiLabel alloc] initWithFrame:CGRectMake(side + kPad, 60.0f, textWidth, titleHeight)] autorelease];
    title.backgroundColor = [UIColor clearColor];
    title.font = PKStoryTitleFont();
    title.textColor = PKTextColor();
    title.numberOfLines = 0;
    title.text = _post.title;
    [header addSubview:title];
    if (parentRow > 0.0f) {
        /* a reply post is hard to read without its original */
        UIButton *parent = [UIButton buttonWithType:UIButtonTypeCustom];
        parent.frame = CGRectMake(side + kPad, 60.0f + titleHeight + 4.0f, textWidth, 30.0f);
        parent.titleLabel.font = PKFont(PKFontWeightMedium, 14.0f);
        parent.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        parent.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        parent.accessibilityLabel = PKText(@"Исходный пост");
        [parent setTitle:_post.parentTitle.length ? [NSString stringWithFormat:PKText(@"Исходный пост: %@"), _post.parentTitle] : PKText(@"Исходный пост") forState:UIControlStateNormal];
        [parent setTitleColor:PKAccentColor() forState:UIControlStateNormal];
        PKAttachPressFeedback(parent);
        [parent addTarget:self action:@selector(openParentPost) forControlEvents:UIControlEventTouchUpInside];
        [header addSubview:parent];
    }
    _table.tableHeaderView = header;
}

#pragma mark actions bar

- (UIButton *)iconButton:(PKIconKind)kind color:(UIColor *)color action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setImage:PKIcon(kind, 20.0f, color) forState:UIControlStateNormal];
    PKAttachPressFeedback(button);
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

/* the site shows these between the post and its thread */
- (void)rebuildActions {
    CGFloat width = _table.bounds.size.width > 0 ? _table.bounds.size.width : self.view.bounds.size.width;
    CGFloat side = PKContentSideInset(width);
    CGFloat y = 0.0f;
    [_actions release];
    _actions = [[UIView alloc] initWithFrame:CGRectZero];
    _actions.backgroundColor = PKCardColor();

    UIView *pill = [[[UIView alloc] initWithFrame:CGRectMake(side + kPad, y + 8.0f, 132.0f, 34.0f)] autorelease];
    pill.backgroundColor = PKControlColor();
    pill.layer.cornerRadius = 17.0f;
    UIButton *up = [self iconButton:PKIconArrowUp color:PKAccentColor() action:@selector(upVote:)];
    up.frame = CGRectMake(0, 0, 44, 34);
    UIButton *down = [self iconButton:PKIconArrowDown color:PKMutedColor() action:@selector(downVote:)];
    down.frame = CGRectMake(88, 0, 44, 34);
    UILabel *score = PKLabel(15, _post.scoreKnown && _post.score < 0 ? PKDangerColor() : PKTextColor(), YES);
    score.text = _post.scoreKnown ? PKCompactScore(_post.score) : @"…";
    score.textAlignment = NSTextAlignmentCenter;
    score.frame = CGRectMake(44, 0, 44, 34);
    [pill addSubview:up]; [pill addSubview:score]; [pill addSubview:down];
    [_actions addSubview:pill];

    UIButton *share = [self iconButton:PKIconShare color:PKMutedColor() action:@selector(shareStory)];
    share.frame = CGRectMake(width - side - kPad - 44.0f, y + 8.0f, 44.0f, 34.0f);
    [_actions addSubview:share];
    y += 50.0f;

    {
        /* paid reactions included, wrapped onto as many rows as it takes. a standing reaction toggles at
           once, the plus chip opens the picker */
        CGFloat left = side + kPad;
        CGFloat available = width - side * 2.0f - kPad * 2.0f;
        CGFloat chipWidth = 68.0f, gap = 6.0f, plusWidth = 44.0f, x = 0.0f;
        for (NSDictionary *reaction in _storyReactions) {
            if (x > 0 && x + chipWidth > available) { x = 0; y += 40.0f; }
            BOOL active = [[reaction objectForKey:@"active"] boolValue];
            UIButton *chip = [UIButton buttonWithType:UIButtonTypeCustom];
            chip.frame = CGRectMake(left + x, y, chipWidth, 34.0f);
            chip.tag = [[reaction objectForKey:@"id"] integerValue];
            chip.backgroundColor = PKControlColor();
            chip.layer.cornerRadius = 17.0f;
            chip.layer.borderWidth = active ? 1.5f : 0.0f;
            chip.layer.borderColor = PKAccentColor().CGColor;
            UILabel *text = PKLabel(14, active ? PKAccentColor() : PKTextColor(), active);
            text.text = [NSString stringWithFormat:@"%@ %@", [reaction objectForKey:@"emoji"], PKCompactScore([[reaction objectForKey:@"count"] integerValue])];
            text.textAlignment = NSTextAlignmentCenter;
            text.frame = chip.bounds;
            text.userInteractionEnabled = NO;
            [chip addSubview:text];
            [chip addTarget:self action:@selector(storyChipTapped:) forControlEvents:UIControlEventTouchUpInside];
            [_actions addSubview:chip];
            x += chipWidth + gap;
        }
        BOOL none = !_storyReactions.count;
        if (!none && x + plusWidth > available) { x = 0; y += 40.0f; }
        UIButton *plus = [UIButton buttonWithType:UIButtonTypeCustom];
        plus.frame = CGRectMake(left + x, y, none ? available : plusWidth, 34.0f);
        plus.backgroundColor = PKControlColor();
        plus.layer.cornerRadius = 17.0f;
        UILabel *plusText = PKLabel(14, PKTextColor(), NO);
        plusText.text = none ? PKText(@"Добавить реакцию") : @"＋";
        plusText.textAlignment = NSTextAlignmentCenter;
        plusText.frame = plus.bounds;
        plusText.userInteractionEnabled = NO;
        [plus addSubview:plusText];
        plus.accessibilityLabel = PKText(@"Добавить реакцию");
        [plus addTarget:self action:@selector(storyReactionsTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_actions addSubview:plus];
        y += 42.0f;
    }

    UILabel *heading = PKLabel(16, PKTextColor(), YES);
    heading.text = _post.comments > 0 ? [NSString stringWithFormat:PKText(@"Комментарии  %ld"), (long)_post.comments] : PKText(@"Комментарии");
    heading.frame = CGRectMake(side + kPad, y + 4.0f, width - side * 2.0f - kPad * 2.0f, 24.0f);
    [_actions addSubview:heading];
    y += 30.0f;
    if (_commentsNote.length) {
        UILabel *note = PKLabel(13, PKMutedColor(), NO);
        note.numberOfLines = 2;
        note.text = _commentsNote;
        note.frame = CGRectMake(side + kPad, y, width - side * 2.0f - kPad * 2.0f, 34.0f);
        [_actions addSubview:note];
        y += 40.0f;
    }
    y += 6.0f;
    UIView *line = [[[UIView alloc] initWithFrame:CGRectMake(0, y - 1.0f, width, 1.0f)] autorelease];
    line.backgroundColor = PKSeparatorColor();
    [_actions addSubview:line];
    _actions.frame = CGRectMake(0, 0, width, y);
}

#pragma mark reactions and voting

- (NSArray *)commonReactionIDs { return [NSArray arrayWithObjects:@15, @1, @6, @8, @12, @13, @5, @36, nil]; }
- (NSArray *)commonReactionTitles { return [NSArray arrayWithObjects:PKText(@"❤️ Сердце"), PKText(@"😂 Смех"), PKText(@"💯 Сто"), PKText(@"🤡 Клоун"), PKText(@"🤦 Фейспалм"), PKText(@"🔥 Огонь"), PKText(@"😡 Злость"), PKText(@"🤔 Задумался"), nil]; }
- (BOOL)reactionIsActive:(NSInteger)reactionID inReactions:(NSArray *)reactions { for (NSDictionary *reaction in reactions) if ([[reaction objectForKey:@"id"] integerValue] == reactionID) return [[reaction objectForKey:@"active"] boolValue]; return NO; }

- (void)pushLoginThen:(void (^)(void))completion {
    PKLoginViewController *login = [[[PKLoginViewController alloc] initWithCompletion:^(BOOL authenticated) {
        if (authenticated && completion) completion();
    }] autorelease];
    [self.navigationController pushViewController:login animated:YES];
}

- (void)sendReaction:(NSInteger)reactionID forComment:(PKComment *)comment {
    BOOL active = [self reactionIsActive:reactionID inReactions:comment ? comment.reactions : _storyReactions];
    [self showToast:PKText(@"Отправка реакции…")];
    NSString *commentID = [[comment.commentID copy] autorelease];
    PKActionCompletion done = ^(NSError *error) {
        if (error) { [self showToast:error.localizedDescription]; return; }
        /* the server answers result:true before the page shows the change, so the toast waits for the reload */
        [_afterLoad release];
        _afterLoad = [^{
            NSArray *now = commentID ? [self reactionsOfCommentID:commentID] : _storyReactions;
            BOOL applied = !now || [self reactionIsActive:reactionID inReactions:now] == !active;
            [self showToast:applied ? (active ? PKText(@"Реакция убрана") : PKText(@"Реакция поставлена")) : PKText(@"Сервер не принял реакцию")];
        } copy];
        [self loadStory];
    };
    if (comment) PKReactComment(comment, reactionID, !active, _storyHTML, done);
    else PKReactStory(_post, reactionID, !active, _storyHTML, done);
}
- (void)storyChipTapped:(UIButton *)chip {
    if (!PKSessionWasAuthenticated()) { [self pushLoginThen:nil]; return; }
    [self sendReaction:chip.tag forComment:nil];
}

- (void)showReactionPickerForComment:(PKComment *)comment {
    NSMutableArray *titles = [NSMutableArray array];
    if (comment) [titles addObjectsFromArray:[NSArray arrayWithObjects:PKText(@"＋ Плюс"), PKText(@"− Минус"), nil]];
    [titles addObjectsFromArray:[self commonReactionTitles]];
    PKReactionPicker *picker = [[[PKReactionPicker alloc] initWithTitles:titles selection:^(NSInteger index) {
        if (comment && index < 2) {
            PKVoteComment(comment, index == 0 ? 1 : -1, _storyHTML, ^(NSError *error) {
                [self showToast:error ? error.localizedDescription : PKText(@"Оценка комментария учтена")];
                if (!error) [self loadStory];
            });
            return;
        }
        NSInteger reactionIndex = index - (comment ? 2 : 0);
        NSArray *ids = [self commonReactionIDs];
        if (reactionIndex < 0 || (NSUInteger)reactionIndex >= ids.count) return;
        [self sendReaction:[[ids objectAtIndex:(NSUInteger)reactionIndex] integerValue] forComment:comment];
    }] autorelease];
    [picker presentInView:self.view];
}
- (void)storyReactionsTapped:(UIButton *)button {
    (void)button;
    if (!PKSessionWasAuthenticated()) { [self pushLoginThen:nil]; return; }
    [self showReactionPickerForComment:nil];
}

- (void)shareStory { PKPresentShareSheet(self.view, _post.title, _post.url); }

- (void)openStoryMedia:(NSDictionary *)selected {
    NSMutableArray *items = [NSMutableArray array];
    for (NSDictionary *item in _blocks) {
        NSString *type = [item objectForKey:@"type"];
        NSString *url = [item objectForKey:@"url"];
        if (([type isEqualToString:@"image"] || [type isEqualToString:@"video"]) && [url isKindOfClass:[NSString class]] && url.length)
            [items addObject:item];
    }
    NSUInteger index = [items indexOfObjectIdenticalTo:selected];
    if (index == NSNotFound) { [self showToast:PKText(@"Медиа недоступно")]; return; }
    PKMediaViewer *viewer = [[[PKMediaViewer alloc] initWithMedia:items title:_post.title index:index] autorelease];
    [self presentModalViewController:viewer animated:YES];
}

- (void)vote:(NSInteger)value {
    if (!_storyHTML.length) return;
    if (!PKSessionWasAuthenticated()) { [self pushLoginThen:^{ [self vote:value]; }]; return; }
    [self showToast:PKText(@"Отправка голоса...")];
    PKVoteStory(_post, value, _storyHTML, ^(NSError *error) {
        [self showToast:error ? error.localizedDescription : PKText(@"Голос учтен")];
        if (!error) [self loadStory];
    });
}
- (void)openParentPost {
    PKPost *parent = PKParentPost(_post);
    if (!parent) return;
    StoryViewController *story = [[[StoryViewController alloc] initWithPost:parent] autorelease];
    [self.navigationController pushViewController:story animated:YES];
}
- (void)openAuthorProfile {
    if (!_post.author.length) return;
    ProfileViewController *profile = [[[ProfileViewController alloc] initWithUsername:_post.author] autorelease];
    [self.navigationController pushViewController:profile animated:YES];
}
/* answers the tap before the request answers */
- (void)upVote:(UIButton *)button { PKPopView(button.imageView, 0.55f); [self vote:1]; }
- (void)downVote:(UIButton *)button { PKPopView(button.imageView, 0.55f); [self vote:-1]; }

#pragma mark comments

- (void)rebuildVisibleComments {
    [_visibleComments removeAllObjects];
    NSInteger hiddenDepth = -1;
    for (PKComment *comment in _comments) {
        if (hiddenDepth >= 0 && comment.indent > hiddenDepth) continue;
        hiddenDepth = -1;
        [_visibleComments addObject:comment];
        if (comment.commentID.length && [_collapsedCommentIDs containsObject:comment.commentID]) hiddenDepth = comment.indent;
    }
}
static const NSInteger kLongBranchComments = 4;

- (void)rebuildDescendants {
    NSUInteger index, next;
    [_descendants removeAllObjects];
    [_commentsByID removeAllObjects];
    for (index = 0; index < _comments.count; index++) {
        PKComment *comment = [_comments objectAtIndex:index];
        if (comment.commentID.length) [_commentsByID setObject:comment forKey:comment.commentID];
        NSInteger count = 0;
        for (next = index + 1; next < _comments.count && ((PKComment *)[_comments objectAtIndex:next]).indent > comment.indent; next++) count++;
        if (comment.commentID.length && count > 0) [_descendants setObject:[NSNumber numberWithInteger:count] forKey:comment.commentID];
    }
}
- (BOOL)commentHasChildren:(PKComment *)comment {
    return comment.commentID.length && [_descendants objectForKey:comment.commentID] != nil;
}
/* 0 for an open branch */
- (NSInteger)hiddenRepliesOfComment:(PKComment *)comment {
    if (!comment.commentID.length || ![_collapsedCommentIDs containsObject:comment.commentID]) return 0;
    return [[_descendants objectForKey:comment.commentID] integerValue];
}
- (NSString *)foldOwnerForVisibleRow:(NSInteger)row {
    if (row <= 0 || (NSUInteger)row >= _visibleComments.count) return nil;
    PKComment *comment = [_visibleComments objectAtIndex:(NSUInteger)row];
    PKComment *previous = [_visibleComments objectAtIndex:(NSUInteger)row - 1];
    if (comment.indent < 1 || previous.indent != comment.indent - 1 || !previous.commentID.length) return nil;
    return [[_descendants objectForKey:previous.commentID] integerValue] >= kLongBranchComments ? previous.commentID : nil;
}
/* nothing when the parent is not in the loaded thread */
- (PKComment *)parentOfComment:(PKComment *)comment {
    if (comment.indent < 1 || !comment.parentID.length) return nil;
    PKComment *parent = [_commentsByID objectForKey:comment.parentID];
    return parent != comment ? parent : nil;
}
- (NSString *)quoteForComment:(PKComment *)comment {
    if (!comment.commentID.length || ![_openQuoteIDs containsObject:comment.commentID]) return nil;
    NSString *body = [self parentOfComment:comment].body;
    if (!body.length) return nil;
    return body.length > 400 ? [[body substringToIndex:400] stringByAppendingString:@"…"] : body;
}
- (void)commentCellDidToggleQuote:(PKCommentCell *)cell {
    NSString *identifier = cell.comment.commentID;
    if (!identifier.length) return;
    if ([_openQuoteIDs containsObject:identifier]) [_openQuoteIDs removeObject:identifier];
    else [_openQuoteIDs addObject:identifier];
    [_table reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationNone];
}
/* a comment inside a folded branch cannot be seen */
- (void)unfoldAncestorsOfFocusedComment {
    if (!_focusCommentID.length) return;
    PKComment *comment = [_commentsByID objectForKey:_focusCommentID];
    NSUInteger steps = 0;
    while (comment && steps++ < 64) {
        PKComment *parent = [self parentOfComment:comment];
        if (!parent) break;
        [_collapsedCommentIDs removeObject:parent.commentID];
        comment = parent;
    }
}
- (void)scrollToFocusedComment {
    if (!_focusCommentID.length) return;
    NSString *identifier = [[_focusCommentID retain] autorelease];
    [_focusCommentID release]; _focusCommentID = nil;
    for (NSUInteger index = 0; index < _visibleComments.count; index++) {
        if (![((PKComment *)[_visibleComments objectAtIndex:index]).commentID isEqualToString:identifier]) continue;
        [_markedCommentID release]; _markedCommentID = [identifier copy];
        [_table reloadData];
        [_table scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:(NSInteger)index inSection:1] atScrollPosition:UITableViewScrollPositionMiddle animated:NO];
        return;
    }
    /* the loaded thread is bounded and the site hides low rated comments */
    [self showToast:PKText(@"Комментарий не найден в загруженной ветке")];
}
- (void)setBranchOfID:(NSString *)identifier collapsed:(BOOL)collapsed {
    if (!identifier.length) return;
    if (collapsed) [_collapsedCommentIDs addObject:identifier];
    else [_collapsedCommentIDs removeObject:identifier];
    [self rebuildVisibleComments];
    [_table reloadSections:[NSIndexSet indexSetWithIndex:1] withRowAnimation:UITableViewRowAnimationFade];
}
- (void)commentCellDidToggleBranch:(PKCommentCell *)cell {
    PKComment *comment = cell.comment;
    if (![self commentHasChildren:comment]) return;
    [self setBranchOfID:comment.commentID collapsed:![_collapsedCommentIDs containsObject:comment.commentID]];
}
- (void)commentCell:(PKCommentCell *)cell didFoldBranchOfID:(NSString *)identifier {
    (void)cell;
    [self setBranchOfID:identifier collapsed:YES];
    /* after a long branch disappears the folded comment can be far above */
    for (NSUInteger index = 0; index < _visibleComments.count; index++) {
        if (![((PKComment *)[_visibleComments objectAtIndex:index]).commentID isEqualToString:identifier]) continue;
        NSIndexPath *path = [NSIndexPath indexPathForRow:(NSInteger)index inSection:1];
        if (![[_table indexPathsForVisibleRows] containsObject:path])
            [_table scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionTop animated:NO];
        break;
    }
}

#pragma mark writing, voting and copying

- (void)presentComposerForParent:(PKComment *)parent {
    PKComposerViewController *composer = [[[PKComposerViewController alloc] initWithStory:_post parent:parent completion:^{
        [self showToast:PKText(@"Комментарий отправлен")];
        [self loadStory];
    }] autorelease];
    UINavigationController *navigation = [[[UINavigationController alloc] initWithRootViewController:composer] autorelease];
    PKStyleNavigationBar(navigation.navigationBar);
    [self presentModalViewController:navigation animated:YES];
}
- (void)composeForParent:(PKComment *)parent {
    if (!PKSessionWasAuthenticated()) { [self pushLoginThen:^{ [self presentComposerForParent:parent]; }]; return; }
    [self presentComposerForParent:parent];
}
- (void)composeTapped { [self composeForParent:nil]; }
- (void)commentCellDidReply:(PKCommentCell *)cell { [self composeForParent:cell.comment]; }
- (void)commentCell:(PKCommentCell *)cell didVote:(NSInteger)vote {
    PKComment *comment = cell.comment;
    if (!comment) return;
    if (!PKSessionWasAuthenticated()) { [self pushLoginThen:nil]; return; }
    [self showToast:PKText(@"Отправка голоса...")];
    PKVoteComment(comment, vote, _storyHTML, ^(NSError *error) {
        [self showToast:error ? error.localizedDescription : PKText(@"Оценка комментария учтена")];
        if (!error) [self loadStory];
    });
}

- (void)presentTextMenuWithTitle:(NSString *)title text:(NSString *)text links:(NSArray *)links reply:(void (^)(void))reply {
    NSMutableArray *titles = [NSMutableArray array];
    NSMutableArray *actions = [NSMutableArray array];
    void (^add)(NSString *, void (^)(void)) = ^(NSString *label, void (^action)(void)) {
        [titles addObject:label];
        [actions addObject:[[action copy] autorelease]];
    };
    if (reply) add(PKText(@"Ответить"), reply);
    if (text.length) add(PKText(@"Копировать текст"), ^{ [UIPasteboard generalPasteboard].string = text; [self showToast:PKText(@"Скопировано")]; });
    for (NSString *link in links) {
        if (titles.count >= 12) break;
        NSString *shown = PKLinkTitle(link);
        add([NSString stringWithFormat:PKText(@"Открыть: %@"), shown], ^{
            NSURL *url = [NSURL URLWithString:link];
            if (url) [[UIApplication sharedApplication] openURL:url];
        });
    }
    if (!titles.count) return;
    PKShowSheet(title, titles, -1, PKText(@"Отмена"), ^(NSInteger index) {
        if (index < 0 || (NSUInteger)index >= actions.count) return;
        void (^action)(void) = [actions objectAtIndex:(NSUInteger)index];
        action();
    });
}
- (void)commentCellDidOpenMenu:(PKCommentCell *)cell {
    PKComment *comment = cell.comment;
    if (!comment) return;
    [self presentTextMenuWithTitle:comment.author text:comment.body links:comment.links reply:^{ [self composeForParent:comment]; }];
}
- (void)storyTextCell:(PKStoryTextCell *)cell didOpenMenuWithText:(NSString *)text links:(NSArray *)links {
    (void)cell;
    [self presentTextMenuWithTitle:nil text:text links:links reply:nil];
}
- (void)openImageURL:(NSString *)url title:(NSString *)title {
    if (!url.length) return;
    PKImageViewerViewController *viewer = [[[PKImageViewerViewController alloc] initWithURL:url title:title] autorelease];
    [self presentModalViewController:viewer animated:YES];
}
- (void)commentCell:(PKCommentCell *)cell didOpenAuthor:(NSString *)author {
    (void)cell;
    if (!author.length) return;
    [self.navigationController pushViewController:[[[ProfileViewController alloc] initWithUsername:author] autorelease] animated:YES];
}
- (void)commentCellDidOpenMedia:(PKCommentCell *)cell { [self openImageURL:cell.comment.mediaURL title:cell.comment.author]; }
- (void)commentCellDidLoadImage:(PKCommentCell *)cell {
    if (![_table indexPathForCell:cell]) return;
    [_table beginUpdates];
    [_table endUpdates];
}
- (void)storyMediaCell:(PKStoryMediaCell *)cell didLoadURL:(NSString *)url size:(CGSize)size {
    if (!url.length || ![_table indexPathForCell:cell]) return;
    NSValue *old = [_mediaDimensions objectForKey:url];
    /* when the shapes agree it is the picture the page reserved a box for, so the row already has its height */
    if (old && fabsf((float)([old CGSizeValue].width * size.height - [old CGSizeValue].height * size.width)) <= 0.01f * [old CGSizeValue].width * size.height) return;
    [_mediaDimensions setObject:[NSValue valueWithCGSize:size] forKey:url];
    [_table beginUpdates];
    [_table endUpdates];
}

#pragma mark table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 2; }
/* a section header would pin under the navigation bar while the thread scrolls, and this bar is too tall for that */
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; return section == 0 ? _blocks.count + 1 : _visibleComments.count; }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        if ((NSUInteger)indexPath.row == _blocks.count) return _actions.frame.size.height;
        NSDictionary *block = [_blocks objectAtIndex:indexPath.row];
        if ([[block objectForKey:@"type"] isEqualToString:@"text"])
            return PKStoryTextHeight([block objectForKey:@"text"], [block objectForKey:@"links"], tableView.bounds.size.width);
        if ([[block objectForKey:@"type"] isEqualToString:@"image"]) {
            NSString *url = [block objectForKey:@"url"];
            NSValue *dimensions = url.length ? [_mediaDimensions objectForKey:url] : nil;
            CGSize size = dimensions ? [dimensions CGSizeValue] : CGSizeZero;
            CGFloat height = (CGFloat)pk_media_height(PKContentWidth(tableView.bounds.size.width), size.width, size.height);
            if (height > 0) return MAX(1.0f, ceilf(height));
        }
        return MIN(360, MAX(210, PKContentWidth(tableView.bounds.size.width) * 0.86));
    }
    PKComment *rowComment = [_visibleComments objectAtIndex:indexPath.row];
    return PKCommentRowHeight(rowComment, tableView.bounds.size.width, [self hiddenRepliesOfComment:rowComment] > 0,
                              [self parentOfComment:rowComment] != nil, [self quoteForComment:rowComment]);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        if ((NSUInteger)indexPath.row == _blocks.count) {
            UITableViewCell *actionsCell = [[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil] autorelease];
            actionsCell.selectionStyle = UITableViewCellSelectionStyleNone;
            actionsCell.backgroundColor = PKCardColor();
            [actionsCell.contentView addSubview:_actions];
            return actionsCell;
        }
        NSDictionary *block = [_blocks objectAtIndex:indexPath.row];
        if ([[block objectForKey:@"type"] isEqualToString:@"text"]) {
            static NSString *textKey = @"story-text";
            PKStoryTextCell *textCell = (PKStoryTextCell *)[tableView dequeueReusableCellWithIdentifier:textKey];
            if (!textCell) textCell = [[[PKStoryTextCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:textKey] autorelease];
            [textCell setText:[block objectForKey:@"text"] links:[block objectForKey:@"links"]];
            textCell.delegate = self;
            return textCell;
        }
        static NSString *mediaKey = @"story-media";
        PKStoryMediaCell *cell = (PKStoryMediaCell *)[tableView dequeueReusableCellWithIdentifier:mediaKey];
        if (!cell) cell = [[[PKStoryMediaCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:mediaKey] autorelease];
        [cell setMedia:block delegate:self];
        return cell;
    }
    static NSString *key = @"comment";
    PKCommentCell *cell = (PKCommentCell *)[tableView dequeueReusableCellWithIdentifier:key];
    if (!cell) cell = [[[PKCommentCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:key] autorelease];
    PKComment *comment = [_visibleComments objectAtIndex:indexPath.row];
    [cell setComment:comment hiddenReplies:[self hiddenRepliesOfComment:comment] foldOwnerID:[self foldOwnerForVisibleRow:indexPath.row]
       replyToAuthor:[self parentOfComment:comment].author quote:[self quoteForComment:comment] delegate:self];
    if (_markedCommentID.length && [comment.commentID isEqualToString:_markedCommentID]) cell.backgroundColor = PKControlColor();
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        if ((NSUInteger)indexPath.row == _blocks.count) return;
        NSDictionary *media = [_blocks objectAtIndex:indexPath.row];
        NSString *type = [media objectForKey:@"type"];
        if ([type isEqualToString:@"video"] || [type isEqualToString:@"image"]) [self openStoryMedia:media];
        return;
    }
    if (!PKSessionWasAuthenticated()) { [self pushLoginThen:nil]; return; }
    PKComment *comment = [_visibleComments objectAtIndex:indexPath.row];
    [self showReactionPickerForComment:comment];
}

- (void)dealloc {
    _requestGeneration++;
    [_afterLoad release];
    _table.delegate = nil;
    _table.dataSource = nil;
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(hideToast) object:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_post release]; [_storyHTML release]; [_table release]; [_comments release]; [_visibleComments release];
    [_collapsedCommentIDs release]; [_focusCommentID release]; [_markedCommentID release]; [_descendants release]; [_commentsByID release]; [_openQuoteIDs release]; [_composeButton release]; [_toast release]; [_actions release];
    [_blocks release]; [_mediaDimensions release]; [_storyReactions release]; [_spinner release];
    [_commentsNote release];
    [super dealloc];
}
@end
