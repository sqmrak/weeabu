#import "post_cell.h"
#import "pk_lang.h"
#import "pk_image.h"
#import "pk_icons.h"
#import "pk_share.h"
#import "pk_theme.h"
#import "pk_motion.h"
#include "pk_media_layout.h"
#import "pk_emoji_label.h"
#import "pk_media_viewer.h"
#import "story_vc.h"
#import <QuartzCore/QuartzCore.h>

#define PK_CHIP_MAX 4

static const CGFloat kPad = 16.0f;
static const CGFloat kAvatarSide = 32.0f;
static const CGFloat kHeaderHeight = 56.0f;
static const CGFloat kRowGap = 10.0f;
static const CGFloat kChipHeight = 26.0f;
static const CGFloat kFooterHeight = 32.0f;
static const NSUInteger kCollapsedExcerptLines = 4;
/* a collapsed card shows four lines, far fewer than this, so the rest of a long post is never measured for
   the list */
static const NSUInteger kExcerptProbeChars = 600;
static const CGFloat kMaxExpandedExcerpt = 1800.0f;
/* the page ships whole posts, some of tens of thousands of characters */
static const NSUInteger kExpandedProbeChars = 6000;
/* a tall picture is cropped and the button opens it */
static const CGFloat kCollapsedPreviewRatio = 1.15f;
static const CGFloat kCollapsedPreviewMax = 480.0f;
static const CGFloat kExpandedPreviewMax = 2400.0f;

typedef struct {
    CGRect avatar;
    CGRect name;
    CGRect sub;
    CGRect title;
    CGRect parent;
    BOOL showParent;
    CGRect excerpt;
    CGRect button;
    CGRect preview;
    CGRect chips[PK_CHIP_MAX];
    NSUInteger chipCount;
    CGRect reactions;
    BOOL showReactions;
    CGRect ratingPill;
    CGRect commentPill;
    CGRect share;
    BOOL showExcerpt;
    BOOL showButton;
    BOOL showPreview;
    BOOL previewCropped;
    CGFloat height;
} PKPostLayout;

static UIFont *PKTitleFont(void) { return PKFont(PKFontWeightBold, 18.0f); }
static UIFont *PKExcerptFont(void) { return PKFont(PKFontWeightRegular, 15.0f); }
static UIFont *PKChipFont(void) { return PKFont(PKFontWeightRegular, 13.0f); }
static UIFont *PKPillFont(void) { return PKFont(PKFontWeightMedium, 14.0f); }

static CGFloat PKTextHeight(NSString *text, UIFont *font, CGFloat width, CGFloat maxHeight) {
    if (!text.length || width < 1.0f) return 0.0f;
    CGFloat height = PKEmojiTextHeight(text, font, width, MAX(maxHeight, font.lineHeight * 2.0f));
    return MIN(maxHeight, MAX(ceilf(font.lineHeight), ceilf(height)));
}

static CGFloat PKTextWidth(NSString *text, UIFont *font) {
    if (!text.length) return 0.0f;
    return ceilf([text sizeWithFont:font].width);
}

static NSString *PKSubline(PKPost *post) {
    if (post.community.length && post.date.length)
        return [NSString stringWithFormat:@"%@  ·  %@", post.community, post.date];
    return post.community.length ? post.community : (post.date.length ? post.date : @"");
}

static NSString *PKCardText(PKPost *post, BOOL expanded) {
    NSString *text = expanded && post.fullText.length ? post.fullText : post.excerpt;
    NSUInteger limit = expanded ? kExpandedProbeChars : kExcerptProbeChars;
    if (text.length <= limit) return text;
    return expanded ? [[text substringToIndex:limit] stringByAppendingString:@"…"] : [text substringToIndex:limit];
}

static PKPostLayout PKLayoutPost(PKPost *post, BOOL expanded, CGFloat cardWidth) {
    PKPostLayout layout;
    memset(&layout, 0, sizeof(layout));
    CGFloat textWidth = MAX(80.0f, cardWidth - kPad * 2.0f);
    CGFloat y;

    layout.avatar = CGRectMake(kPad, 12.0f, kAvatarSide, kAvatarSide);
    layout.name = CGRectMake(kPad + kAvatarSide + 10.0f, 11.0f, textWidth - kAvatarSide - 10.0f - 24.0f, 18.0f);
    layout.sub = CGRectMake(layout.name.origin.x, 29.0f, layout.name.size.width, 16.0f);
    y = kHeaderHeight;

    CGFloat titleLine = ceilf(PKTitleFont().lineHeight);
    BOOL more = NO;
    CGFloat titleFull = PKTextHeight(post.title, PKTitleFont(), textWidth, 260.0f);
    CGFloat titleHeight = expanded ? titleFull : MIN(titleFull, titleLine * 3.0f);
    more = titleFull > titleHeight + 0.5f;
    layout.title = CGRectMake(kPad, y, textWidth, titleHeight);
    y += titleHeight;

    /* the reader wonders what a reply answers right here */
    if (post.parentURL.length) {
        layout.showParent = YES;
        layout.parent = CGRectMake(kPad, y + 2.0f, textWidth, 28.0f);
        y += 30.0f;
    }

    NSString *text = PKCardText(post, expanded);
    if (text.length) {
        CGFloat full = PKTextHeight(text, PKExcerptFont(), textWidth, kMaxExpandedExcerpt);
        CGFloat shown = expanded ? full : MIN(full, ceilf(PKExcerptFont().lineHeight) * kCollapsedExcerptLines);
        if (shown > 0.0f) {
            y += kRowGap;
            layout.showExcerpt = YES;
            layout.excerpt = CGRectMake(kPad, y, textWidth, shown);
            y += shown;
        }
        more = more || full > shown + 0.5f || (!expanded && post.excerpt.length > kExcerptProbeChars);
    }
    /* the site ships the part behind its cut inside the card */
    more = more || post.fullText.length > post.excerpt.length;

    if (post.imageURL.length) {
        CGFloat natural = (CGFloat)pk_media_height(cardWidth, post.imageWidth, post.imageHeight);
        CGFloat height;
        if (natural <= 0) {
            /* a fixed box that fits the picture keeps the row from moving when it arrives */
            height = floorf(cardWidth * 0.66f);
        } else if (expanded) {
            height = MIN(natural, kExpandedPreviewMax);
            layout.previewCropped = natural > height + 0.5f;
        } else {
            CGFloat cap = floorf(MIN(cardWidth * kCollapsedPreviewRatio, kCollapsedPreviewMax));
            height = MIN(natural, cap);
            layout.previewCropped = natural > height + 0.5f;
            more = more || layout.previewCropped;
        }
        height = MAX(1.0f, ceilf(height));
        y += kRowGap;
        layout.showPreview = YES;
        layout.preview = CGRectMake(0.0f, y, cardWidth, height);
        y += height;
    }

    layout.showButton = expanded || more;
    if (layout.showButton) {
        y += 4.0f;
        layout.button = CGRectMake(kPad, y, textWidth, 28.0f);
        y += 28.0f;
    }

    if (post.tags.count) {
        CGFloat x = kPad;
        NSUInteger index;
        y += 10.0f;
        for (index = 0; index < post.tags.count && layout.chipCount < PK_CHIP_MAX; index++) {
            CGFloat width = PKTextWidth([post.tags objectAtIndex:index], PKChipFont()) + 20.0f;
            if (x + width > cardWidth - kPad) break;
            layout.chips[layout.chipCount++] = CGRectMake(x, y, width, kChipHeight);
            x += width + 8.0f;
        }
        if (layout.chipCount) y += kChipHeight;
        else y -= 10.0f;
    }

    if (post.reactions.count) {
        y += 10.0f;
        layout.showReactions = YES;
        layout.reactions = CGRectMake(kPad, y, textWidth, 22.0f);
        y += 22.0f;
    }

    y += 10.0f;
    {
        NSString *score = post.scoreKnown ? PKCompactScore(post.score) : @"…";
        NSString *comments = [NSString stringWithFormat:@"%ld", (long)post.comments];
        CGFloat ratingWidth = 8.0f + 18.0f + 6.0f + PKTextWidth(score, PKPillFont()) + 6.0f + 18.0f + 8.0f;
        CGFloat commentWidth = 10.0f + 18.0f + 6.0f + PKTextWidth(comments, PKPillFont()) + 12.0f;
        layout.ratingPill = CGRectMake(kPad, y, ratingWidth, kFooterHeight);
        layout.commentPill = CGRectMake(kPad + ratingWidth + 8.0f, y, commentWidth, kFooterHeight);
        layout.share = CGRectMake(cardWidth - kPad - 40.0f, y, 40.0f, kFooterHeight);
    }
    y += kFooterHeight + 10.0f;
    layout.height = y;
    return layout;
}

/* the table asks for every row height on each reload, so each (post, expansion, width) is worked out once.
   dropped whole when it grows */
static PKPostLayout PKCachedLayout(PKPost *post, BOOL expanded, CGFloat cardWidth) {
    static NSMutableDictionary *cache;
    static const NSUInteger kLimit = 300;
    if (!post.url.length) return PKLayoutPost(post, expanded, cardWidth);
    if (!cache) cache = [[NSMutableDictionary alloc] init];
    /* the language changes the words a card measures */
    static NSUInteger filledUnder;
    if (filledUnder != PKThemeRevision()) {
        [cache removeAllObjects];
        filledUnder = PKThemeRevision();
    }
    NSString *key = [NSString stringWithFormat:@"%@|%d|%.1f|%d|%ld|%lu|%.0f:%.0f", post.url, expanded ? 1 : 0, cardWidth, post.scoreKnown ? 1 : 0, (long)post.score,
                     (unsigned long)post.reactions.count, post.imageWidth, post.imageHeight];
    NSValue *stored = [cache objectForKey:key];
    PKPostLayout layout;
    if (stored) {
        [stored getValue:&layout];
        return layout;
    }
    layout = PKLayoutPost(post, expanded, cardWidth);
    if (cache.count >= kLimit) [cache removeAllObjects];
    [cache setObject:[NSValue valueWithBytes:&layout objCType:@encode(PKPostLayout)] forKey:key];
    return layout;
}

CGFloat PKPostCellHeightForWidth(PKPost *post, BOOL expanded, CGFloat width) {
    if (!post) return 72.0f;
    CGFloat cardWidth = width - (PKContentSideInset(width) + 10.0f) * 2.0f;
    return kRowGap + PKCachedLayout(post, expanded, cardWidth).height;
}

void PKOpenParentPost(UINavigationController *navigation, PKPost *post) {
    PKPost *parent = PKParentPost(post);
    if (!parent) return;
    StoryViewController *story = [[StoryViewController alloc] initWithPost:parent];
    [navigation pushViewController:story animated:YES];
    [story release];
}

void PKPresentPostMedia(UIViewController *presenter, PKPost *post) {
    PKMediaViewer *viewer;
    if (post.media.count) viewer = [[PKMediaViewer alloc] initWithMedia:post.media title:post.title index:0];
    else if (post.imageURL.length) viewer = [[PKMediaViewer alloc] initWithImageURLs:[NSArray arrayWithObject:post.imageURL] title:post.title index:0];
    else return;
    [presenter presentModalViewController:viewer animated:YES];
    [viewer release];
}

/* four subviews each, two per row, are the first thing a 3GS stutters on */
@interface PKPillView : UIView {
    UIImage *_leading;
    UIImage *_trailing;
    NSString *_text;
    UIColor *_ink;
}
- (void)setLeading:(UIImage *)leading text:(NSString *)text trailing:(UIImage *)trailing ink:(UIColor *)ink;
@end

@implementation PKPillView
- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.userInteractionEnabled = NO;
    }
    return self;
}
/* half of whatever height the layout gives, so the ends stay round */
- (void)layoutSubviews {
    [super layoutSubviews];
    self.layer.cornerRadius = self.bounds.size.height / 2.0f;
}
- (void)setLeading:(UIImage *)leading text:(NSString *)text trailing:(UIImage *)trailing ink:(UIColor *)ink {
    [_leading release]; _leading = [leading retain];
    [_trailing release]; _trailing = [trailing retain];
    [_text release]; _text = [text copy];
    [_ink release]; _ink = [ink retain];
    [self setNeedsDisplay];
}
- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGFloat height = self.bounds.size.height;
    CGFloat x = _trailing ? 8.0f : 10.0f;
    if (_leading) {
        [_leading drawInRect:CGRectMake(x, floorf((height - 18.0f) / 2.0f), 18.0f, 18.0f)];
        x += 24.0f;
    }
    [_ink set];
    UIFont *font = PKPillFont();
    CGFloat textWidth = PKTextWidth(_text, font);
    [_text drawAtPoint:CGPointMake(x, floorf((height - font.lineHeight) / 2.0f)) withFont:font];
    x += textWidth + 6.0f;
    if (_trailing) [_trailing drawInRect:CGRectMake(x, floorf((height - 18.0f) / 2.0f), 18.0f, 18.0f)];
}
- (void)dealloc {
    [_leading release]; [_trailing release]; [_text release]; [_ink release];
    [super dealloc];
}
@end

@interface PKPostCell () {
    UIView *_card;
    UIImageView *_avatar;
    UILabel *_avatarLetter;
    UILabel *_nameLabel;
    UIButton *_authorButton;
    UILabel *_subLabel;
    UILabel *_titleLabel;
    UILabel *_excerptLabel;
    UILabel *_reactionsLabel;
    UIButton *_expandButton;
    UIButton *_parentButton;
    UIButton *_chips[PK_CHIP_MAX];
    PKPillView *_ratingPill;
    PKPillView *_commentPill;
    UIButton *_shareButton;
    UIImageView *_preview;
    UIImageView *_playBadge;
    UIImageView *_videoMark;
    UILabel *_countBadge;
    NSString *_representedURL;
    NSString *_representedAvatarURL;
    BOOL _expanded;
    PKPost *_post;
    id<PKPostCellDelegate> _delegate;
}
@end

@implementation PKPostCell

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
        NSUInteger index;
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.backgroundColor = [UIColor clearColor];
        self.contentView.backgroundColor = [UIColor clearColor];
        _card = [[UIView alloc] initWithFrame:CGRectZero];
        _card.layer.borderWidth = 0.5f;
        _card.clipsToBounds = YES;
        [self.contentView addSubview:_card];

        _avatar = [[UIImageView alloc] initWithFrame:CGRectZero];
        _avatar.contentMode = UIViewContentModeScaleAspectFill;
        _avatar.clipsToBounds = YES;
        _avatar.layer.cornerRadius = kAvatarSide / 2.0f;
        _avatarLetter = [PKLabel(15, PKMutedColor(), YES) retain];
        _avatarLetter.textAlignment = NSTextAlignmentCenter;
        _nameLabel = [PKLabel(14, PKTextColor(), YES) retain];
        _subLabel = [PKLabel(12, PKMutedColor(), NO) retain];
        _titleLabel = [[PKEmojiLabel alloc] initWithFrame:CGRectZero];
        _titleLabel.backgroundColor = [UIColor clearColor];
        _titleLabel.font = PKTitleFont();
        _excerptLabel = [[PKEmojiLabel alloc] initWithFrame:CGRectZero];
        _excerptLabel.backgroundColor = [UIColor clearColor];
        _excerptLabel.font = PKExcerptFont();
        _reactionsLabel = [PKLabel(14, PKMutedColor(), NO) retain];
        _expandButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _expandButton.titleLabel.font = PKFont(PKFontWeightMedium, 14.0f);
        _expandButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        PKAttachPressFeedback(_expandButton);
        [_expandButton addTarget:self action:@selector(expandTapped) forControlEvents:UIControlEventTouchUpInside];

        _parentButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _parentButton.titleLabel.font = PKFont(PKFontWeightMedium, 14.0f);
        _parentButton.titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        _parentButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        _parentButton.accessibilityLabel = PKText(@"Исходный пост");
        PKAttachPressFeedback(_parentButton);
        [_parentButton addTarget:self action:@selector(parentTapped) forControlEvents:UIControlEventTouchUpInside];

        _preview = [[UIImageView alloc] initWithFrame:CGRectZero];
        _preview.contentMode = UIViewContentModeScaleAspectFit;
        _preview.clipsToBounds = YES;
        _preview.userInteractionEnabled = YES;
        [_preview addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(previewTapped)] autorelease]];
        _countBadge = [PKLabel(12, [UIColor whiteColor], YES) retain];
        _countBadge.backgroundColor = [UIColor colorWithWhite:0 alpha:0.62f];
        _countBadge.textAlignment = NSTextAlignmentCenter;
        _countBadge.layer.cornerRadius = 10.0f;
        _countBadge.clipsToBounds = YES;
        _countBadge.userInteractionEnabled = NO;
        _playBadge = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 52, 52)];
        _playBadge.backgroundColor = [UIColor colorWithWhite:0 alpha:0.62f];
        _playBadge.layer.cornerRadius = 26.0f;
        _playBadge.contentMode = UIViewContentModeCenter;
        _playBadge.image = PKIcon(PKIconPlay, 26.0f, [UIColor whiteColor]);

        _videoMark = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 18, 18)];
        for (index = 0; index < PK_CHIP_MAX; index++) {
            UIButton *chip = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
            chip.titleLabel.font = PKChipFont();
            chip.layer.cornerRadius = 13.0f;
            chip.layer.borderWidth = 0.0f;
            chip.tag = (NSInteger)index;
            PKAttachPressFeedback(chip);
            [chip addTarget:self action:@selector(chipTapped:) forControlEvents:UIControlEventTouchUpInside];
            _chips[index] = chip;
        }
        _ratingPill = [[PKPillView alloc] initWithFrame:CGRectZero];
        _commentPill = [[PKPillView alloc] initWithFrame:CGRectZero];
        _shareButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        PKAttachPressFeedback(_shareButton);
        [_shareButton addTarget:self action:@selector(shareTapped) forControlEvents:UIControlEventTouchUpInside];

        [_card addSubview:_avatar];
        [_card addSubview:_avatarLetter];
        [_card addSubview:_videoMark];
        [_card addSubview:_nameLabel];
        /* one clear button over both, two more subviews are two more hit-tests on old phones */
        _authorButton = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _authorButton.accessibilityLabel = PKText(@"Профиль автора");
        [_authorButton addTarget:self action:@selector(authorTapped) forControlEvents:UIControlEventTouchUpInside];
        [_card addSubview:_subLabel];
        [_card addSubview:_titleLabel];
        [_card addSubview:_excerptLabel];
        [_card addSubview:_reactionsLabel];
        [_card addSubview:_expandButton];
        [_card addSubview:_parentButton];
        [_card addSubview:_preview];
        [_preview addSubview:_playBadge];
        [_preview addSubview:_countBadge];
        for (index = 0; index < PK_CHIP_MAX; index++) [_card addSubview:_chips[index]];
        [_card addSubview:_ratingPill];
        [_card addSubview:_commentPill];
        [_card addSubview:_shareButton];
        [_card addSubview:_authorButton];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self.contentView.layer removeAnimationForKey:@"pk.list.enter"];
    [_expandButton.layer removeAnimationForKey:@"pk.bounce"];
    [_parentButton.layer removeAnimationForKey:@"pk.bounce"];
    [_shareButton.layer removeAnimationForKey:@"pk.bounce"];
    for (NSUInteger index = 0; index < PK_CHIP_MAX; index++) [_chips[index].layer removeAnimationForKey:@"pk.bounce"];
    [_representedURL release]; _representedURL = nil;
    [_representedAvatarURL release]; _representedAvatarURL = nil;
    _preview.image = nil;
    _avatar.image = nil;
    [_post release]; _post = nil;
    _delegate = nil;
}

- (void)setPost:(PKPost *)post expanded:(BOOL)expanded
       delegate:(id<PKPostCellDelegate>)delegate {
    NSUInteger index;
    _expanded = expanded;
    _delegate = delegate;
    [_post release]; _post = [post retain];

    NSString *author = post.author.length ? post.author : @"Weeabu";
    _nameLabel.text = author;
    _subLabel.text = PKSubline(post);
    _avatarLetter.text = [[author substringToIndex:1] uppercaseString];
    _titleLabel.text = post.title;
    _reactionsLabel.text = PKReactionSummary(post.reactions, 5);
    _excerptLabel.text = PKCardText(post, expanded);
    for (index = 0; index < PK_CHIP_MAX; index++) {
        if (index < post.tags.count) [_chips[index] setTitle:[post.tags objectAtIndex:index] forState:UIControlStateNormal];
    }
    [_expandButton setTitle:expanded ? PKText(@"Скрыть") : PKText(@"Показать полностью") forState:UIControlStateNormal];
    [_parentButton setTitle:post.parentTitle.length ? [NSString stringWithFormat:PKText(@"Исходный пост: %@"), post.parentTitle] : PKText(@"Исходный пост") forState:UIControlStateNormal];

    [_representedAvatarURL release];
    _representedAvatarURL = [post.avatarURL copy];
    _avatar.image = nil;
    _avatarLetter.hidden = NO;
    if (_representedAvatarURL.length) {
        NSString *requestedAvatar = [[_representedAvatarURL copy] autorelease];
        PKLoadImage(requestedAvatar, ^(UIImage *image) {
            if (![requestedAvatar isEqualToString:_representedAvatarURL]) return;
            _avatar.image = image;
            _avatarLetter.hidden = image != nil;
        });
    }

    [_representedURL release];
    _representedURL = [post.imageURL copy];
    _preview.image = nil;
    if (_representedURL.length) {
        NSString *requestedURL = [[_representedURL copy] autorelease];
        PKLoadImage(requestedURL, ^(UIImage *image) {
            if (![requestedURL isEqualToString:_representedURL]) return;
            _preview.image = image;
        });
    }
    [self applyTheme];
    [self setNeedsLayout];
}

- (BOOL)isExpanded { return _expanded; }
- (void)parentTapped {
    if (_post.parentURL.length && [_delegate respondsToSelector:@selector(postCellDidOpenParent:)])
        [_delegate postCellDidOpenParent:self];
}
- (void)previewTapped {
    if (_post.imageURL.length && [_delegate respondsToSelector:@selector(postCellDidOpenMedia:)])
        [_delegate postCellDidOpenMedia:self];
}
- (PKPost *)post { return _post; }
- (void)expandTapped {
    if ([_delegate respondsToSelector:@selector(postCellDidToggleExpanded:)])
        [_delegate postCellDidToggleExpanded:self];
}
- (void)chipTapped:(UIButton *)chip {
    NSUInteger index = (NSUInteger)chip.tag;
    if (index < _post.tags.count && [_delegate respondsToSelector:@selector(postCell:didTapTag:)])
        [_delegate postCell:self didTapTag:[_post.tags objectAtIndex:index]];
}
- (void)authorTapped {
    if (_post.author.length && [_delegate respondsToSelector:@selector(postCell:didTapAuthor:)])
        [_delegate postCell:self didTapAuthor:_post.author];
}
- (void)shareTapped {
    PKPresentShareSheet(self.window, _post.title, _post.url);
}

- (void)applyTheme {
    NSUInteger index;
    UIColor *muted = PKMutedColor();
    _card.backgroundColor = PKCardColor();
    _card.layer.borderColor = PKHairlineColor().CGColor;
    _avatar.backgroundColor = PKControlColor();
    _avatarLetter.textColor = muted;
    _nameLabel.textColor = PKTextColor();
    _subLabel.textColor = muted;
    _titleLabel.textColor = PKTextColor();
    _excerptLabel.textColor = PKTextColor();
    _reactionsLabel.textColor = muted;
    _preview.backgroundColor = PKMediaWellColor();
    [_expandButton setTitleColor:PKAccentColor() forState:UIControlStateNormal];
    [_parentButton setTitleColor:PKAccentColor() forState:UIControlStateNormal];
    for (index = 0; index < PK_CHIP_MAX; index++) {
        _chips[index].backgroundColor = PKControlColor();
        _chips[index].layer.borderColor = PKHairlineColor().CGColor;
        [_chips[index] setTitleColor:muted forState:UIControlStateNormal];
    }
    _ratingPill.backgroundColor = PKControlColor();
    _commentPill.backgroundColor = PKControlColor();
    [_ratingPill setLeading:PKIcon(PKIconArrowUp, 18.0f, muted) text:(_post.scoreKnown ? PKCompactScore(_post.score) : @"…")
                   trailing:PKIcon(PKIconArrowDown, 18.0f, muted) ink:(_post.scoreKnown && _post.score < 0 ? PKDangerColor() : PKTextColor())];
    [_commentPill setLeading:PKIcon(PKIconComment, 18.0f, muted)
                        text:[NSString stringWithFormat:@"%ld", (long)_post.comments]
                    trailing:nil ink:PKTextColor()];
    [_shareButton setImage:PKIcon(PKIconShare, 22.0f, muted) forState:UIControlStateNormal];
    _videoMark.image = PKIcon(PKIconPlay, 18.0f, muted);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    NSUInteger index;
    CGFloat width = self.contentView.bounds.size.width;
    CGFloat side = PKContentSideInset(width) + 10.0f;
    CGFloat cardWidth = MAX(1.0f, width - side * 2.0f);
    PKPostLayout layout = PKCachedLayout(_post, _expanded, cardWidth);
    _card.frame = CGRectMake(side, kRowGap, cardWidth, self.contentView.bounds.size.height - kRowGap);
    _card.layer.cornerRadius = 12.0f;
    CGFloat dx = 0.0f;

    _avatar.frame = CGRectOffset(layout.avatar, dx, 0);
    _avatarLetter.frame = _avatar.frame;
    _nameLabel.frame = CGRectOffset(layout.name, dx, 0);
    _subLabel.frame = CGRectOffset(layout.sub, dx, 0);
    _authorButton.frame = CGRectInset(CGRectUnion(_avatar.frame, CGRectUnion(_nameLabel.frame, _subLabel.frame)), -4.0f, -4.0f);
    _titleLabel.numberOfLines = _expanded ? 0 : 3;
    _titleLabel.frame = CGRectOffset(layout.title, dx, 0);
    _parentButton.hidden = !layout.showParent;
    _parentButton.frame = CGRectOffset(layout.parent, dx, 0);
    _excerptLabel.numberOfLines = _expanded ? 0 : (NSInteger)kCollapsedExcerptLines;
    _excerptLabel.hidden = !layout.showExcerpt;
    _excerptLabel.frame = CGRectOffset(layout.excerpt, dx, 0);
    _expandButton.hidden = !layout.showButton;
    _expandButton.frame = CGRectOffset(layout.button, dx, 0);
    _preview.hidden = !layout.showPreview;
    _preview.frame = CGRectOffset(layout.preview, dx, 0);
    /* the full height shows once the card is expanded */
    _preview.contentMode = layout.previewCropped ? UIViewContentModeScaleAspectFill : UIViewContentModeScaleAspectFit;
    {
        NSUInteger total = _post.media.count;
        _countBadge.hidden = total < 2;
        if (total >= 2) {
            _countBadge.text = [NSString stringWithFormat:@"1/%lu", (unsigned long)total];
            CGFloat badgeWidth = MAX(34.0f, ceilf([_countBadge.text sizeWithFont:_countBadge.font].width) + 16.0f);
            _countBadge.frame = CGRectMake(layout.preview.size.width - badgeWidth - 10.0f, 10.0f, badgeWidth, 20.0f);
        }
    }
    _playBadge.hidden = !_post.hasVideo;
    _videoMark.hidden = !_post.hasVideo || layout.showPreview;
    _videoMark.frame = CGRectMake(cardWidth - kPad - 18.0f + dx, 19.0f, 18.0f, 18.0f);
    _playBadge.center = CGPointMake(layout.preview.size.width / 2.0f, layout.preview.size.height / 2.0f);
    for (index = 0; index < PK_CHIP_MAX; index++) {
        _chips[index].hidden = index >= layout.chipCount;
        if (index < layout.chipCount) _chips[index].frame = CGRectOffset(layout.chips[index], dx, 0);
    }
    _reactionsLabel.hidden = !layout.showReactions;
    _reactionsLabel.frame = CGRectOffset(layout.reactions, dx, 0);
    _ratingPill.frame = CGRectOffset(layout.ratingPill, dx, 0);
    _commentPill.frame = CGRectOffset(layout.commentPill, dx, 0);
    _shareButton.frame = CGRectOffset(layout.share, dx, 0);
}

- (void)dealloc {
    NSUInteger index;
    for (index = 0; index < PK_CHIP_MAX; index++) [_chips[index] release];
    [_card release]; [_avatar release]; [_avatarLetter release]; [_nameLabel release]; [_subLabel release];
    [_titleLabel release]; [_excerptLabel release]; [_reactionsLabel release]; [_expandButton release]; [_parentButton release]; [_authorButton release]; [_ratingPill release];
    [_commentPill release]; [_shareButton release]; [_preview release]; [_playBadge release]; [_videoMark release]; [_countBadge release];
    [_representedURL release]; [_representedAvatarURL release]; [_post release];
    [super dealloc];
}
@end
