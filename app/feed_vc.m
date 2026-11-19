#import "feed_vc.h"
#import "pk_api.h"
#import "pk_lang.h"
#import "pk_theme.h"
#import "pk_motion.h"
#import <QuartzCore/QuartzCore.h>
#import "post_cell.h"
#import "profile_vc.h"
#import "search_vc.h"
#import "story_vc.h"
#import "pk_auth.h"

#define PK_FEED_SECTIONS 4

/* the name is dropped when it does not fit, a 320 point iphone holds only one */
static NSString *const PKSubscriptionsSection = @"subs";

static NSArray *PKFeedSections(void) {
    return [NSArray arrayWithObjects:@"hot", @"best", @"new", PKSubscriptionsSection, nil];
}

@interface PKFeedBar : UIControl {
    UIImageView *_mascot;
    UILabel *_name;
    UIButton *_buttons[PK_FEED_SECTIONS];
    UIView *_line;
    NSUInteger _selected;
    CGFloat _preferredWidth;
}
@property(nonatomic, assign) NSUInteger selectedIndex;
@property(nonatomic, assign) CGFloat preferredWidth;
- (void)applyTheme;
@end

@implementation PKFeedBar
@synthesize preferredWidth = _preferredWidth;
- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        _preferredWidth = frame.size.width;
        _mascot = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"Icon-mascot.png"]];
        [self addSubview:_mascot];
        _name = [[UILabel alloc] initWithFrame:CGRectZero];
        _name.backgroundColor = [UIColor clearColor];
        _name.font = PKFont(PKFontWeightMedium, 17);
        _name.text = @"Weeabu";
        [self addSubview:_name];
        for (NSUInteger i = 0; i < PK_FEED_SECTIONS; i++) {
            _buttons[i] = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
            _buttons[i].tag = (NSInteger)i;
            _buttons[i].titleLabel.font = PKFont(PKFontWeightMedium, 14);
            PKAttachPressFeedback(_buttons[i]);
            [_buttons[i] addTarget:self action:@selector(select:) forControlEvents:UIControlEventTouchUpInside];
            [self addSubview:_buttons[i]];
        }
        _line = [[UIView alloc] initWithFrame:CGRectZero];
        [self addSubview:_line];
        self.isAccessibilityElement = NO;
        _mascot.isAccessibilityElement = YES;
        _mascot.accessibilityLabel = @"Weeabu";
        [self applyTheme];
    }
    return self;
}
- (CGSize)intrinsicContentSize { return CGSizeMake(_preferredWidth, 30); }
- (NSUInteger)selectedIndex { return _selected; }
- (void)setSelectedIndex:(NSUInteger)selected {
    if (selected >= PK_FEED_SECTIONS) return;
    _selected = selected;
    [self applyTheme];
    [self setNeedsLayout];
}
- (void)select:(UIButton *)button {
    if ((NSUInteger)button.tag == _selected) return;
    CGRect before = _line.layer.presentationLayer ? [(CALayer *)_line.layer.presentationLayer frame] : _line.frame;
    self.selectedIndex = (NSUInteger)button.tag;
    [self layoutIfNeeded];
    PKAnimateSpring(_line, CGAffineTransformMakeTranslation(before.origin.x - _line.frame.origin.x, 0), 1.0f, PK_SPRING_SPATIAL, 0, @"pk.line");
    PKPopView(button.titleLabel, 0.88f);
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (void)applyTheme {
    NSArray *titles = [NSArray arrayWithObjects:PKText(@"Горячее"), PKText(@"Лучшее"), PKText(@"Свежее"), PKText(@"Моя лента"), nil];
    _name.textColor = PKBarContentColor();
    _line.backgroundColor = PKAccentColor();
    for (NSUInteger i = 0; i < PK_FEED_SECTIONS; i++) {
        [_buttons[i] setTitle:[titles objectAtIndex:i] forState:UIControlStateNormal];
        [_buttons[i] setTitleColor:i == _selected ? PKBarContentColor() : PKMutedColor() forState:UIControlStateNormal];
    }
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;
    CGFloat pad = 12;
    CGFloat widths[PK_FEED_SECTIONS];
    CGFloat sections = 0;
    for (NSUInteger i = 0; i < PK_FEED_SECTIONS; i++) {
        widths[i] = ceilf([[_buttons[i] titleForState:UIControlStateNormal] sizeWithFont:_buttons[i].titleLabel.font].width) + pad;
        sections += widths[i];
    }
    CGFloat nameWidth = ceilf([_name.text sizeWithFont:_name.font].width);
    CGFloat x = 0;
    _mascot.frame = CGRectMake(x, floorf((height - 24) / 2), 24, 24);
    x += 24 + 6;
    BOOL showName = x + nameWidth + 8 + sections <= width;
    _name.hidden = !showName;
    if (showName) {
        _name.frame = CGRectMake(x, 0, nameWidth, height);
        x += nameWidth + 8;
    }
    if (!showName) x += 2;
    CGFloat spare = width - x - sections;
    CGFloat extra = spare > 0 ? floorf(MIN(spare, 8 * PK_FEED_SECTIONS) / PK_FEED_SECTIONS) : 0;
    for (NSUInteger i = 0; i < PK_FEED_SECTIONS; i++) {
        CGFloat w = widths[i] + extra;
        _buttons[i].frame = CGRectMake(x, 0, w, height);
        if (i == _selected) _line.frame = CGRectMake(x + 6, height - 3, w - 12, 3);
        x += w;
    }
}
- (void)dealloc {
    for (NSUInteger i = 0; i < PK_FEED_SECTIONS; i++) [_buttons[i] release];
    [_mascot release]; [_name release]; [_line release];
    [super dealloc];
}
@end

@interface FeedViewController () <PKPostCellDelegate> {
    PKFeedBar *_bar;
    NSMutableArray *_posts;
    NSMutableSet *_expanded;
    NSString *_section;
    UILabel *_message;
    UIRefreshControl *_refresh;
    NSUInteger _generation;
    NSInteger _nextPage;
    BOOL _loading;
    BOOL _hasMore;
    CGFloat _layoutWidth;
}
@end

@implementation FeedViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Weeabu";
    _posts = [[NSMutableArray alloc] init];
    _expanded = [[NSMutableSet alloc] init];
    NSInteger defaultIndex = PKDefaultFeedIndex();
    _section = [[PKFeedSections() objectAtIndex:(NSUInteger)defaultIndex] copy];
    _bar = [[PKFeedBar alloc] initWithFrame:CGRectMake(0, 0, 300, 30)];
    _bar.selectedIndex = (NSUInteger)defaultIndex;
    [_bar addTarget:self action:@selector(sectionChanged:) forControlEvents:UIControlEventValueChanged];
    self.navigationItem.titleView = _bar;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _message = [PKLabel(14, PKMutedColor(), NO) retain];
    _message.textAlignment = NSTextAlignmentCenter;
    _message.numberOfLines = 0;
    self.tableView.backgroundView = _message;
    Class refreshClass = NSClassFromString(@"UIRefreshControl");
    if (refreshClass) {
        _refresh = [[refreshClass alloc] init];
        [_refresh addTarget:self action:@selector(refresh) forControlEvents:UIControlEventValueChanged];
        [self.tableView addSubview:_refresh];
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:PKThemeDidChangeNotification object:nil];
    [self applyTheme];
    [self refresh];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    /* signing in or out on the profile tab changes what the subscriptions section shows */
    if ([_section isEqualToString:PKSubscriptionsSection] && !_loading &&
        (PKSessionWasAuthenticated() ? !_posts.count : (_posts.count != 0 || _hasMore)))
        [self refresh];
    [self.tableView reloadData];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    /* ios 5 and 6 center the title view and never widen it */
    CGRect barBounds = self.navigationController.navigationBar.bounds;
    if (barBounds.size.width > 0) {
        CGFloat barWidth = barBounds.size.width - 16;
        CGFloat barHeight = MIN(30, barBounds.size.height);
        if (fabsf((float)(_bar.preferredWidth - barWidth)) >= 0.5f || fabsf((float)(_bar.frame.size.height - barHeight)) >= 0.5f) {
            _bar.preferredWidth = barWidth;
            _bar.frame = CGRectMake(0, 0, barWidth, barHeight);
            if ([_bar respondsToSelector:@selector(invalidateIntrinsicContentSize)]) [_bar invalidateIntrinsicContentSize];
        }
    }
    CGFloat width = self.tableView.bounds.size.width;
    if (width <= 0 || fabsf((float)(width - _layoutWidth)) < 0.5f) return;
    _layoutWidth = width;
    [self.tableView reloadData];
}
- (void)themeChanged:(NSNotification *)notification {
    (void)notification;
    [self applyTheme];
    [self.tableView reloadData];
}
- (void)applyTheme {
    self.tableView.backgroundColor = PKBackgroundColor();
    _message.textColor = PKMutedColor();
    [_bar applyTheme];
}
- (void)sectionChanged:(PKFeedBar *)bar {
    [_section release];
    _section = [[PKFeedSections() objectAtIndex:bar.selectedIndex] copy];
    [self refresh];
}
- (void)refresh {
    _generation++;
    _loading = NO;
    _nextPage = 1;
    _hasMore = YES;
    /* the subscriptions page of a signed out visitor is a login form, which the post scanner reads as an
       empty feed */
    if ([_section isEqualToString:PKSubscriptionsSection] && !PKSessionWasAuthenticated()) {
        [_posts removeAllObjects]; [_expanded removeAllObjects];
        _hasMore = NO;
        [_refresh endRefreshing];
        _message.text = PKText(@"Войдите в профиль, чтобы видеть свою ленту");
        [self.tableView reloadData];
        return;
    }
    [self loadPageReplacing:YES];
}
- (void)loadPageReplacing:(BOOL)replace {
    if (_loading || (!_hasMore && !replace)) { [_refresh endRefreshing]; return; }
    _loading = YES;
    _message.text = _posts.count ? @"" : PKText(@"Загружаем ленту…");
    NSUInteger generation = _generation;
    NSInteger page = replace ? 1 : _nextPage;
    NSString *section = [[_section copy] autorelease];
    PKLoadFeed(section, page, ^(NSArray *posts, NSError *error) {
        if (generation != _generation || ![section isEqualToString:_section]) return;
        _loading = NO;
        [_refresh endRefreshing];
        if (error) {
            _message.text = [NSString stringWithFormat:PKText(@"Не удалось загрузить ленту\n%@\n\nПотяните вниз, чтобы повторить"), error.localizedDescription];
            [self.tableView reloadData];
            return;
        }
        if (replace) { [_posts removeAllObjects]; [_expanded removeAllObjects]; }
        PKAppendUniquePosts(_posts, posts);
        _hasMore = posts.count > 0;
        _nextPage = page + 1;
        _message.text = _posts.count ? @"" : PKText(@"В этой ленте пока ничего нет");
        [self.tableView reloadData];
        if (replace && _posts.count) PKAnimateListAppearance(self.tableView);
    });
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section; return _posts.count + (_hasMore && _posts.count ? 1 : 0);
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ((NSUInteger)indexPath.row == _posts.count) return 54;
    PKPost *post = [_posts objectAtIndex:indexPath.row];
    return PKPostCellHeightForWidth(post, [_expanded containsObject:post.url], tableView.bounds.size.width);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ((NSUInteger)indexPath.row == _posts.count) {
        static NSString *more = @"feed-more";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:more];
        if (!cell) cell = [[[PKReadableCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:more] autorelease];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.font = PKFont(PKFontWeightMedium, 15);
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = PKAccentColor();
        cell.textLabel.text = _loading ? PKText(@"Загрузка…") : PKText(@"Показать ещё");
        return cell;
    }
    static NSString *identifier = @"feed-post";
    PKPostCell *cell = (PKPostCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[PKPostCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    PKPost *post = [_posts objectAtIndex:indexPath.row];
    [cell setPost:post expanded:[_expanded containsObject:post.url] delegate:self];
    return cell;
}
- (void)postCellDidOpenMedia:(PKPostCell *)cell {
    PKPresentPostMedia(self, cell.post);
}
- (void)postCellDidOpenParent:(PKPostCell *)cell {
    PKOpenParentPost(self.navigationController, cell.post);
}
- (void)postCellDidToggleExpanded:(PKPostCell *)cell {
    PKPost *post = cell.post;
    if (!post.url.length) return;
    if ([_expanded containsObject:post.url]) [_expanded removeObject:post.url];
    else [_expanded addObject:post.url];
    [self.tableView beginUpdates];
    [self.tableView endUpdates];
}
- (void)postCell:(PKPostCell *)cell didTapAuthor:(NSString *)author {
    (void)cell;
    if (!author.length) return;
    ProfileViewController *profile = [[[ProfileViewController alloc] initWithUsername:author] autorelease];
    [self.navigationController pushViewController:profile animated:YES];
}
- (void)postCell:(PKPostCell *)cell didTapTag:(NSString *)tag {
    (void)cell;
    if (!tag.length) return;
    SearchViewController *search = [[[SearchViewController alloc] initWithQuery:tag] autorelease];
    [self.navigationController pushViewController:search animated:YES];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if ((NSUInteger)indexPath.row == _posts.count) { [self loadPageReplacing:NO]; return; }
    StoryViewController *story = [[[StoryViewController alloc] initWithPost:[_posts objectAtIndex:indexPath.row]] autorelease];
    [self.navigationController pushViewController:story animated:YES];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (_posts.count && _hasMore && !_loading && scrollView.contentOffset.y + scrollView.bounds.size.height > scrollView.contentSize.height - 180)
        [self loadPageReplacing:NO];
}
- (void)dealloc {
    _generation++;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_bar release]; [_posts release]; [_expanded release]; [_section release];
    [_message release]; [_refresh release];
    [super dealloc];
}
@end
