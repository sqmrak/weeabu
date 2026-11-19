#import "user_lists_vc.h"
#import "pk_profile.h"
#import "pk_api.h"
#import "pk_image.h"
#import "pk_lang.h"
#import "pk_theme.h"
#import "pk_motion.h"
#import "pk_dialog.h"
#import "pk_v1.h"
#import "pk_auth.h"
#import "post_cell.h"
#import "story_vc.h"
#import "profile_vc.h"
#import "search_vc.h"
#import <QuartzCore/QuartzCore.h>

/* drawn by hand, so a long list does not carry four subviews a row */
@interface PKImageRowCell : PKReadableCell {
    NSString *_representedURL;
}
- (void)setTitle:(NSString *)title subtitle:(NSString *)subtitle imageURL:(NSString *)imageURL round:(BOOL)round;
@end

@implementation PKImageRowCell
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier])) {
        (void)style;
        self.imageView.contentMode = UIViewContentModeScaleAspectFill;
        self.imageView.clipsToBounds = YES;
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat side = 44.0f;
    self.imageView.frame = CGRectMake(16, floorf((self.contentView.bounds.size.height - side) / 2), side, side);
    CGFloat x = 16 + side + 12;
    CGRect title = self.textLabel.frame, sub = self.detailTextLabel.frame;
    title.origin.x = x; title.size.width = self.contentView.bounds.size.width - x - 16;
    sub.origin.x = x; sub.size.width = title.size.width;
    self.textLabel.frame = title;
    self.detailTextLabel.frame = sub;
}
- (void)setTitle:(NSString *)title subtitle:(NSString *)subtitle imageURL:(NSString *)imageURL round:(BOOL)round {
    self.backgroundColor = PKCardColor();
    self.textLabel.font = PKFont(PKFontWeightMedium, 15);
    self.textLabel.textColor = PKTextColor();
    self.textLabel.text = title;
    self.detailTextLabel.font = PKFont(PKFontWeightRegular, 13);
    self.detailTextLabel.textColor = PKMutedColor();
    self.detailTextLabel.text = subtitle;
    self.imageView.backgroundColor = PKControlColor();
    self.imageView.layer.cornerRadius = round ? 22.0f : 8.0f;
    self.imageView.image = nil;
    [_representedURL release];
    _representedURL = [imageURL copy];
    if (!imageURL.length) return;
    NSString *requested = [[imageURL copy] autorelease];
    PKLoadImage(requested, ^(UIImage *image) {
        if (![requested isEqualToString:_representedURL]) return;
        self.imageView.image = image;
        [self setNeedsLayout];
    });
}
- (void)dealloc { [_representedURL release]; [super dealloc]; }
@end

static void PKStyleListTable(UITableView *table) {
    table.backgroundView = nil;
    table.backgroundColor = PKBackgroundColor();
    table.separatorColor = PKSeparatorColor();
    table.rowHeight = 64.0f;
}

@interface PKAwardsViewController () { NSArray *_awards; NSString *_name; }
@end

@implementation PKAwardsViewController
- (id)initWithAwards:(NSArray *)awards name:(NSString *)name {
    if ((self = [super initWithStyle:UITableViewStylePlain])) { _awards = [awards copy]; _name = [name copy]; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = PKText(@"Награды");
    PKStyleListTable(self.tableView);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:PKThemeDidChangeNotification object:nil];
}
- (void)themeChanged:(NSNotification *)note { (void)note; PKStyleListTable(self.tableView); [self.tableView reloadData]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return (NSInteger)_awards.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"award";
    PKImageRowCell *cell = (PKImageRowCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[PKImageRowCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    PKAward *award = [_awards objectAtIndex:(NSUInteger)indexPath.row];
    NSMutableArray *parts = [NSMutableArray array];
    if (award.date.length >= 10) [parts addObject:[award.date substringToIndex:10]];
    if (award.storyTitle.length) [parts addObject:award.storyTitle];
    [cell setTitle:award.title subtitle:[parts componentsJoinedByString:@" · "] imageURL:award.imageURL round:NO];
    cell.selectionStyle = award.link.length ? UITableViewCellSelectionStyleGray : UITableViewCellSelectionStyleNone;
    cell.accessoryType = award.link.length ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    PKAward *award = [_awards objectAtIndex:(NSUInteger)indexPath.row];
    if (!award.link.length) return;
    PKPost *post = [[[PKPost alloc] init] autorelease];
    post.url = [@"https://pikabu.ru" stringByAppendingString:award.link];
    post.title = award.storyTitle;
    NSRange underscore = [award.link rangeOfString:@"_" options:NSBackwardsSearch];
    if (underscore.location != NSNotFound) post.storyID = [award.link substringFromIndex:underscore.location + 1];
    [self.navigationController pushViewController:[[[StoryViewController alloc] initWithPost:post] autorelease] animated:YES];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [_awards release]; [_name release]; [super dealloc]; }
@end

@interface PKCommunitiesViewController () { NSArray *_communities; NSString *_name; }
@end

@implementation PKCommunitiesViewController
- (id)initWithCommunities:(NSArray *)communities name:(NSString *)name {
    if ((self = [super initWithStyle:UITableViewStylePlain])) { _communities = [communities copy]; _name = [name copy]; }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = PKText(@"Сообщества");
    PKStyleListTable(self.tableView);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:PKThemeDidChangeNotification object:nil];
}
- (void)themeChanged:(NSNotification *)note { (void)note; PKStyleListTable(self.tableView); [self.tableView reloadData]; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return (NSInteger)_communities.count; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"community";
    PKImageRowCell *cell = (PKImageRowCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[PKImageRowCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    PKCommunity *community = [_communities objectAtIndex:(NSUInteger)indexPath.row];
    [cell setTitle:community.name subtitle:[@"pikabu.ru/community/" stringByAppendingString:community.link] imageURL:community.avatarURL round:YES];
    cell.selectionStyle = UITableViewCellSelectionStyleGray;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    PKCommunity *community = [_communities objectAtIndex:(NSUInteger)indexPath.row];
    NSString *escaped = [community.link stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSURL *url = escaped.length ? [NSURL URLWithString:[@"https://pikabu.ru/community/" stringByAppendingString:escaped]] : nil;
    if (url) [[UIApplication sharedApplication] openURL:url];
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [_communities release]; [_name release]; [super dealloc]; }
@end

@interface PKUserPostsViewController () <PKPostCellDelegate> {
    NSString *_username;
    UILabel *_message;
    NSMutableArray *_posts;
    NSMutableSet *_expanded;
    NSUInteger _generation;
    NSInteger _nextPage;
    BOOL _loading;
    BOOL _hasMore;
}
@end

@implementation PKUserPostsViewController
- (id)initWithUsername:(NSString *)username {
    if ((self = [super initWithStyle:UITableViewStylePlain])) _username = [username copy];
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = PKText(@"Посты");
    _posts = [[NSMutableArray alloc] init];
    _expanded = [[NSMutableSet alloc] init];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _message = [PKLabel(14, PKMutedColor(), NO) retain];
    _message.textAlignment = NSTextAlignmentCenter;
    _message.numberOfLines = 0;
    /* a failed first page has no row to tap, so the message retries */
    _message.userInteractionEnabled = YES;
    [_message addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(loadNextPage)] autorelease]];
    self.tableView.backgroundView = _message;
    _nextPage = 1;
    _hasMore = YES;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:PKThemeDidChangeNotification object:nil];
    [self applyTheme];
    [self loadNextPage];
}
- (void)themeChanged:(NSNotification *)note { (void)note; [self applyTheme]; [self.tableView reloadData]; }
- (void)applyTheme {
    self.tableView.backgroundColor = PKBackgroundColor();
    _message.textColor = PKMutedColor();
}
- (void)loadNextPage {
    if (_loading || !_hasMore) return;
    _loading = YES;
    if (!_posts.count) _message.text = PKText(@"Загружаем посты…");
    NSUInteger generation = _generation;
    NSInteger page = _nextPage;
    PKLoadUserPosts(_username, page, ^(NSArray *posts, NSError *error) {
        if (generation != _generation) return;
        _loading = NO;
        if (error) {
            _message.text = _posts.count ? @"" : [NSString stringWithFormat:PKText(@"Не удалось загрузить посты\n%@\n\nНажмите, чтобы повторить"), error.localizedDescription];
            [self.tableView reloadData];
            return;
        }
        PKAppendUniquePosts(_posts, posts);
        /* a page with nothing new is the end of the list */
        _hasMore = posts.count > 0;
        _nextPage = page + 1;
        _message.text = _posts.count ? @"" : PKText(@"У автора пока нет постов");
        [self.tableView reloadData];
        if (page == 1 && _posts.count) PKAnimateListAppearance(self.tableView);
    });
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView; (void)section; return (NSInteger)_posts.count + (_hasMore && _posts.count ? 1 : 0);
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ((NSUInteger)indexPath.row == _posts.count) return 54;
    PKPost *post = [_posts objectAtIndex:(NSUInteger)indexPath.row];
    return PKPostCellHeightForWidth(post, [_expanded containsObject:post.url], tableView.bounds.size.width);
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ((NSUInteger)indexPath.row == _posts.count) {
        static NSString *more = @"user-more";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:more];
        if (!cell) cell = [[[PKReadableCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:more] autorelease];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.font = PKFont(PKFontWeightMedium, 15);
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = PKAccentColor();
        cell.textLabel.text = _loading ? PKText(@"Загрузка…") : PKText(@"Показать ещё");
        return cell;
    }
    static NSString *identifier = @"user-post";
    PKPostCell *cell = (PKPostCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[PKPostCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    PKPost *post = [_posts objectAtIndex:(NSUInteger)indexPath.row];
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
- (void)postCell:(PKPostCell *)cell didTapTag:(NSString *)tag {
    (void)cell;
    if (!tag.length) return;
    [self.navigationController pushViewController:[[[SearchViewController alloc] initWithQuery:tag] autorelease] animated:YES];
}
- (void)postCell:(PKPostCell *)cell didTapAuthor:(NSString *)author {
    (void)cell;
    /* the author on every card is the one already open */
    if (!author.length || [author caseInsensitiveCompare:_username] == NSOrderedSame) return;
    [self.navigationController pushViewController:[[[ProfileViewController alloc] initWithUsername:author] autorelease] animated:YES];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if ((NSUInteger)indexPath.row == _posts.count) { [self loadNextPage]; [tableView deselectRowAtIndexPath:indexPath animated:YES]; return; }
    [self.navigationController pushViewController:[[[StoryViewController alloc] initWithPost:[_posts objectAtIndex:(NSUInteger)indexPath.row]] autorelease] animated:YES];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (_posts.count && _hasMore && !_loading && scrollView.contentOffset.y + scrollView.bounds.size.height > scrollView.contentSize.height - 180)
        [self loadNextPage];
}
- (void)dealloc {
    _generation++;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_username release]; [_message release]; [_posts release]; [_expanded release];
    [super dealloc];
}
@end

/* one function lays out and draws, so height and drawing cannot drift apart */
@interface PKTextRowCell : PKReadableCell {
    UILabel *_top;
    UILabel *_reply;
    UILabel *_body;
    UILabel *_meta;
    UIView *_dot;
}
- (void)setTop:(NSString *)top reply:(NSString *)reply body:(NSString *)body meta:(NSString *)meta fresh:(BOOL)fresh;
+ (CGFloat)heightForTop:(NSString *)top reply:(NSString *)reply body:(NSString *)body meta:(NSString *)meta width:(CGFloat)width;
@end

static CGFloat PKTextHeight(NSString *text, UIFont *font, CGFloat width, NSInteger lines) {
    if (!text.length) return 0;
    CGFloat line = ceilf(font.lineHeight);
    CGSize fit = [text sizeWithFont:font constrainedToSize:CGSizeMake(width, line * (CGFloat)lines + 1) lineBreakMode:NSLineBreakByTruncatingTail];
    return MIN(ceilf(fit.height), line * (CGFloat)lines);
}

@implementation PKTextRowCell
- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:style reuseIdentifier:identifier])) {
        self.selectionStyle = UITableViewCellSelectionStyleGray;
        _top = [PKLabel(12, PKMutedColor(), YES) retain];
        _reply = [PKLabel(12, PKMutedColor(), NO) retain]; _reply.numberOfLines = 2;
        _body = [PKLabel(15, PKTextColor(), NO) retain]; _body.numberOfLines = 6;
        _meta = [PKLabel(12, PKMutedColor(), NO) retain];
        _dot = [[UIView alloc] initWithFrame:CGRectZero];
        _dot.layer.cornerRadius = 4.0f;
        for (UIView *view in [NSArray arrayWithObjects:_top, _reply, _body, _meta, _dot, nil]) [self.contentView addSubview:view];
    }
    return self;
}
+ (CGFloat)heightForTop:(NSString *)top reply:(NSString *)reply body:(NSString *)body meta:(NSString *)meta width:(CGFloat)width {
    CGFloat inner = width - 32.0f;
    CGFloat height = 12.0f;
    height += top.length ? PKTextHeight(top, PKFont(PKFontWeightBold, 12), inner, 1) + 4.0f : 0;
    height += reply.length ? PKTextHeight(reply, PKFont(PKFontWeightRegular, 12), inner, 2) + 4.0f : 0;
    height += body.length ? PKTextHeight(body, PKFont(PKFontWeightRegular, 15), inner, 6) + 6.0f : 0;
    height += meta.length ? PKTextHeight(meta, PKFont(PKFontWeightRegular, 12), inner, 1) : 0;
    return MAX(56.0f, height + 12.0f);
}
- (void)setTop:(NSString *)top reply:(NSString *)reply body:(NSString *)body meta:(NSString *)meta fresh:(BOOL)fresh {
    self.backgroundColor = PKCardColor();
    _top.text = top; _top.textColor = PKMutedColor();
    _reply.text = reply; _reply.textColor = PKMutedColor();
    _body.text = body; _body.textColor = PKTextColor();
    _meta.text = meta; _meta.textColor = PKMutedColor();
    _dot.backgroundColor = PKAccentColor();
    _dot.hidden = !fresh;
    [self setNeedsLayout];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.contentView.bounds.size.width, inner = width - 32.0f, y = 12.0f;
    if (_top.text.length) { CGFloat h = PKTextHeight(_top.text, _top.font, inner, 1); _top.frame = CGRectMake(16, y, inner, h); y += h + 4; } else _top.frame = CGRectZero;
    if (_reply.text.length) { CGFloat h = PKTextHeight(_reply.text, _reply.font, inner, 2); _reply.frame = CGRectMake(16, y, inner, h); y += h + 4; } else _reply.frame = CGRectZero;
    if (_body.text.length) { CGFloat h = PKTextHeight(_body.text, _body.font, inner, 6); _body.frame = CGRectMake(16, y, inner, h); y += h + 6; } else _body.frame = CGRectZero;
    if (_meta.text.length) { _meta.frame = CGRectMake(16, y, inner - 14, PKTextHeight(_meta.text, _meta.font, inner, 1)); } else _meta.frame = CGRectZero;
    _dot.frame = CGRectMake(width - 24, 14, 8, 8);
}
- (void)dealloc { [_top release]; [_reply release]; [_body release]; [_meta release]; [_dot release]; [super dealloc]; }
@end

static NSString *PKDateText(long time) {
    static NSDateFormatter *formatter;
    if (!formatter) { formatter = [[NSDateFormatter alloc] init]; [formatter setDateFormat:@"dd.MM.yyyy HH:mm"]; }
    return time > 0 ? [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)time]] : @"";
}

@interface PKMyCommentsViewController () {
    NSMutableArray *_items;
    UILabel *_message;
    NSUInteger _generation;
    NSInteger _sort;
    NSInteger _nextPage;
    BOOL _loading;
    BOOL _hasMore;
}
@end

@implementation PKMyCommentsViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = PKText(@"Мои комментарии");
    _items = [[NSMutableArray alloc] init];
    _sort = 1;
    self.tableView.separatorColor = PKSeparatorColor();
    _message = [PKLabel(14, PKMutedColor(), NO) retain];
    _message.textAlignment = NSTextAlignmentCenter;
    _message.numberOfLines = 0;
    _message.userInteractionEnabled = YES;
    [_message addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(retry)] autorelease]];
    self.tableView.backgroundView = _message;
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:PKText(@"Сортировка") style:UIBarButtonItemStylePlain target:self action:@selector(chooseSort)] autorelease];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:PKThemeDidChangeNotification object:nil];
    [self applyTheme];
    [self restart];
}
- (void)themeChanged:(NSNotification *)note { (void)note; [self applyTheme]; [self.tableView reloadData]; }
- (void)applyTheme { self.tableView.backgroundColor = PKBackgroundColor(); _message.textColor = PKMutedColor(); self.tableView.separatorColor = PKSeparatorColor(); }
- (void)chooseSort {
    PKShowSheet(PKText(@"Сортировка"), [NSArray arrayWithObjects:PKText(@"Сначала новые"), PKText(@"Актуальные"), nil], -1, nil, ^(NSInteger index) {
        if (index < 0 || (index + 1) == _sort) return;
        _sort = index + 1;
        [self restart];
    });
}
- (void)restart {
    _generation++;
    _loading = NO;
    _hasMore = YES;
    _nextPage = 1;
    [_items removeAllObjects];
    [self.tableView reloadData];
    [self loadNextPage];
}
- (void)retry { if (!_items.count) { _loading = NO; [self loadNextPage]; } }
- (void)loadNextPage {
    if (_loading || !_hasMore) return;
    _loading = YES;
    if (!_items.count) _message.text = PKText(@"Загружаем комментарии…");
    NSUInteger generation = _generation;
    NSInteger page = _nextPage, sort = _sort;
    PKCurrentUserID(^(NSNumber *userID, NSError *idError) {
        if (generation != _generation) return;
        if (idError) { [self failed:idError]; return; }
        PKLoadMyComments(userID, sort, page, ^(NSArray *comments, NSError *error) {
            if (generation != _generation) return;
            if (error) { [self failed:error]; return; }
            _loading = NO;
            [_items addObjectsFromArray:comments];
            _hasMore = comments.count > 0;
            _nextPage = page + 1;
            _message.text = _items.count ? @"" : PKText(@"Вы ещё ничего не комментировали");
            [self.tableView reloadData];
        });
    });
}
- (void)failed:(NSError *)error {
    _loading = NO;
    if (PKV1IsUnauthorized(error)) {
        _message.text = PKText(@"API Пикабу не знает об этом входе. Нажмите, чтобы подтвердить пароль");
        PKPromptApiSession(^(BOOL opened) { if (opened) [self restart]; });
        return;
    }
    if (_items.count) { PKShowNotice(PKText(@"Не удалось загрузить комментарии"), error.localizedDescription); return; }
    _message.text = [NSString stringWithFormat:PKText(@"Не удалось загрузить комментарии\n%@\n\nНажмите, чтобы повторить"), error.localizedDescription];
}
- (NSString *)topFor:(PKMyComment *)comment { return comment.storyTitle; }
- (NSString *)replyFor:(PKMyComment *)comment {
    if (!comment.parentText.length) return @"";
    return [NSString stringWithFormat:@"↳ %@: %@", comment.parentAuthor.length ? comment.parentAuthor : @"…", comment.parentText];
}
- (NSString *)metaFor:(PKMyComment *)comment {
    NSString *score = comment.rating > 0 ? [NSString stringWithFormat:@"+%@", PKCompactScore(comment.rating)] : PKCompactScore(comment.rating);
    NSString *date = PKDateText(comment.time);
    return date.length ? [NSString stringWithFormat:@"%@  ·  %@", score, date] : score;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return (NSInteger)_items.count + (_hasMore && _items.count ? 1 : 0); }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ((NSUInteger)indexPath.row == _items.count) return 54;
    PKMyComment *comment = [_items objectAtIndex:(NSUInteger)indexPath.row];
    return [PKTextRowCell heightForTop:[self topFor:comment] reply:[self replyFor:comment] body:comment.text meta:[self metaFor:comment] width:PKContentWidth(tableView.bounds.size.width)];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ((NSUInteger)indexPath.row == _items.count) {
        static NSString *more = @"mine-more";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:more];
        if (!cell) cell = [[[PKReadableCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:more] autorelease];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.font = PKFont(PKFontWeightMedium, 15);
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = PKAccentColor();
        cell.textLabel.text = _loading ? PKText(@"Загрузка…") : PKText(@"Показать ещё");
        return cell;
    }
    static NSString *identifier = @"mine";
    PKTextRowCell *cell = (PKTextRowCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[PKTextRowCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    PKMyComment *comment = [_items objectAtIndex:(NSUInteger)indexPath.row];
    [cell setTop:[self topFor:comment] reply:[self replyFor:comment] body:comment.text meta:[self metaFor:comment] fresh:NO];
    return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ((NSUInteger)indexPath.row == _items.count) { [self loadNextPage]; return; }
    PKMyComment *comment = [_items objectAtIndex:(NSUInteger)indexPath.row];
    if (!comment.storyURL.length) return;
    PKPost *post = [[[PKPost alloc] init] autorelease];
    post.url = comment.storyURL;
    post.title = comment.storyTitle;
    post.storyID = comment.storyID;
    [self.navigationController pushViewController:[[[StoryViewController alloc] initWithPost:post focusCommentID:comment.commentID] autorelease] animated:YES];
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (_items.count && _hasMore && !_loading && scrollView.contentOffset.y + scrollView.bounds.size.height > scrollView.contentSize.height - 180) [self loadNextPage];
}
- (void)dealloc {
    _generation++;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_items release]; [_message release];
    [super dealloc];
}
@end

@interface PKNotificationsViewController () {
    NSArray *_notices;
    NSNumber *_userID;
    UILabel *_message;
    NSUInteger _generation;
}
@end

@implementation PKNotificationsViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = PKText(@"Уведомления");
    self.tableView.separatorColor = PKSeparatorColor();
    _message = [PKLabel(14, PKMutedColor(), NO) retain];
    _message.textAlignment = NSTextAlignmentCenter;
    _message.numberOfLines = 0;
    _message.userInteractionEnabled = YES;
    [_message addGestureRecognizer:[[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(reload)] autorelease]];
    self.tableView.backgroundView = _message;
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:PKText(@"Ещё") style:UIBarButtonItemStylePlain target:self action:@selector(openMenu)] autorelease];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:PKThemeDidChangeNotification object:nil];
    [self applyTheme];
    [self reload];
}
- (void)themeChanged:(NSNotification *)note { (void)note; [self applyTheme]; [self.tableView reloadData]; }
- (void)applyTheme { self.tableView.backgroundColor = PKBackgroundColor(); _message.textColor = PKMutedColor(); self.tableView.separatorColor = PKSeparatorColor(); }
- (void)failed:(NSError *)error {
    if (PKV1IsUnauthorized(error)) {
        _message.text = PKText(@"API Пикабу не знает об этом входе. Нажмите, чтобы подтвердить пароль");
        PKPromptApiSession(^(BOOL opened) { if (opened) [self reload]; });
        return;
    }
    if (_notices.count) { PKShowNotice(PKText(@"Не удалось выполнить действие"), error.localizedDescription); return; }
    _message.text = [NSString stringWithFormat:PKText(@"Не удалось загрузить уведомления\n%@\n\nНажмите, чтобы повторить"), error.localizedDescription];
}
- (void)reload {
    NSUInteger generation = ++_generation;
    if (!_notices.count) _message.text = PKText(@"Загружаем уведомления…");
    PKCurrentUserID(^(NSNumber *userID, NSError *idError) {
        if (generation != _generation) return;
        if (idError) { [self failed:idError]; return; }
        [_userID release]; _userID = [userID retain];
        PKLoadNotifications(userID, ^(NSArray *notices, NSError *error) {
            if (generation != _generation) return;
            if (error) { [self failed:error]; return; }
            [_notices release]; _notices = [notices copy];
            _message.text = _notices.count ? @"" : PKText(@"Новых уведомлений нет");
            [self.tableView reloadData];
        });
    });
}
- (void)openMenu {
    if (!_userID) return;
    PKShowSheet(nil, [NSArray arrayWithObjects:PKText(@"Отметить прочитанными"), PKText(@"Очистить все"), nil], 1, nil, ^(NSInteger index) {
        if (index == 0) [self run:@"mark_as_read"];
        else if (index == 1) {
            PKShowAlert(PKText(@"Очистить все уведомления?"), nil, [NSArray arrayWithObjects:PKText(@"Отмена"), PKText(@"Очистить")  , nil], 1, YES, ^(NSInteger choice) {
                if (choice == 1) [self run:@"remove_all"];
            });
        }
    });
}
- (void)run:(NSString *)action {
    PKNotificationAction(_userID, action, ^(NSError *error) {
        if (error) { [self failed:error]; return; }
        [self reload];
    });
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; (void)section; return (NSInteger)_notices.count; }
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    PKNotice *notice = [_notices objectAtIndex:(NSUInteger)indexPath.row];
    return [PKTextRowCell heightForTop:nil reply:nil body:notice.text meta:notice.date width:PKContentWidth(tableView.bounds.size.width)];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"notice";
    PKTextRowCell *cell = (PKTextRowCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[PKTextRowCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
    PKNotice *notice = [_notices objectAtIndex:(NSUInteger)indexPath.row];
    [cell setTop:nil reply:nil body:notice.text meta:notice.date fresh:notice.isNew];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    return cell;
}
- (void)dealloc {
    _generation++;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_notices release]; [_userID release]; [_message release];
    [super dealloc];
}
@end
