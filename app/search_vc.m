#import "search_vc.h"
#import "pk_api.h"
#import "pk_lang.h"
#import "pk_theme.h"
#import "pk_motion.h"
#import "post_cell.h"
#import "profile_vc.h"
#import "story_vc.h"
#import <QuartzCore/QuartzCore.h>

@interface SearchViewController () <UITextFieldDelegate, PKPostCellDelegate> {
    UIView *_searchHeader;
    UITextField *_field;
    UILabel *_message;
    NSMutableArray *_posts;
    NSMutableSet *_expanded;
    NSString *_initialQuery;
    NSString *_query;
    NSUInteger _generation;
    NSInteger _nextPage;
    BOOL _loading;
    BOOL _hasMore;
    CGFloat _layoutWidth;
}
@end

@implementation SearchViewController
- (id)initWithQuery:(NSString *)query {
    if ((self = [super initWithStyle:UITableViewStylePlain])) _initialQuery = [query copy];
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = PKText(@"Поиск");
    _posts = [[NSMutableArray alloc] init];
    _expanded = [[NSMutableSet alloc] init];
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _searchHeader = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 64)];
    _searchHeader.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _field = [[UITextField alloc] initWithFrame:CGRectZero];
    _field.layer.cornerRadius = 12;
    _field.font = PKFont(PKFontWeightRegular, 16);
    _field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    _field.placeholder = PKText(@"Посты, теги и авторы");
    _field.clearButtonMode = UITextFieldViewModeWhileEditing;
    _field.returnKeyType = UIReturnKeySearch;
    _field.delegate = self;
    UIImageView *icon = [[[UIImageView alloc] initWithImage:[UIImage imageNamed:@"Icon-nav-search-normal.png"]] autorelease];
    icon.contentMode = UIViewContentModeCenter;
    icon.frame = CGRectMake(0, 0, 44, 48);
    _field.leftView = icon;
    _field.leftViewMode = UITextFieldViewModeAlways;
    [_searchHeader addSubview:_field];
    self.tableView.tableHeaderView = _searchHeader;
    _message = [PKLabel(14, PKMutedColor(), NO) retain];
    _message.textAlignment = NSTextAlignmentCenter;
    _message.numberOfLines = 0;
    _message.text = PKText(@"Найдите что-нибудь интересное");
    self.tableView.backgroundView = _message;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:PKThemeDidChangeNotification object:nil];
    [self applyTheme];
    if (_initialQuery.length) {
        _field.text = _initialQuery;
        [self startSearch:_initialQuery];
    }
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = self.tableView.bounds.size.width;
    if (width <= 0 || fabsf((float)(width - _layoutWidth)) < 0.5f) return;
    _layoutWidth = width;
    CGRect frame = _searchHeader.frame; frame.size.width = width; _searchHeader.frame = frame;
    _field.frame = CGRectMake(PKContentSideInset(width) + 16, 8, PKContentWidth(width) - 32, 48);
    self.tableView.tableHeaderView = _searchHeader;
    [self.tableView reloadData];
}
- (void)themeChanged:(NSNotification *)notification {
    (void)notification;
    self.title = PKText(@"Поиск");
    _field.placeholder = PKText(@"Посты, теги и авторы");
    [self applyTheme];
    [self.tableView reloadData];
}
- (void)applyTheme {
    self.tableView.backgroundColor = PKBackgroundColor();
    _searchHeader.backgroundColor = PKBackgroundColor();
    _field.backgroundColor = PKCardColor();
    _field.textColor = PKTextColor();
    _field.keyboardAppearance = PKDarkThemeEnabled() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    _message.textColor = PKMutedColor();
}
- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [field resignFirstResponder];
    NSString *text = [field.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (text.length) [self startSearch:text];
    return YES;
}
- (void)startSearch:(NSString *)query {
    _generation++;
    _loading = NO;
    [_query release];
    _query = [query copy];
    [_posts removeAllObjects];
    [_expanded removeAllObjects];
    _nextPage = 1;
    _hasMore = YES;
    [self.tableView reloadData];
    [self loadNextPage];
}
- (void)loadNextPage {
    if (_loading || !_hasMore || !_query.length) return;
    _loading = YES;
    if (!_posts.count) _message.text = PKText(@"Ищем…");
    NSUInteger generation = _generation;
    NSInteger page = _nextPage;
    NSString *query = [[_query copy] autorelease];
    PKSearch(query, page, ^(NSArray *posts, NSError *error) {
        if (generation != _generation || ![query isEqualToString:_query]) return;
        _loading = NO;
        if (error) {
            _message.text = [NSString stringWithFormat:PKText(@"Поиск не удался\n%@\n\nПовторите запрос"), error.localizedDescription];
            [self.tableView reloadData];
            return;
        }
        PKAppendUniquePosts(_posts, posts);
        _hasMore = posts.count > 0;
        _nextPage = page + 1;
        _message.text = _posts.count ? @"" : PKText(@"Ничего не найдено");
        [self.tableView reloadData];
        if (page == 1 && _posts.count) PKAnimateListAppearance(self.tableView);
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
        static NSString *more = @"search-more";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:more];
        if (!cell) cell = [[[PKReadableCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:more] autorelease];
        cell.backgroundColor = [UIColor clearColor];
        cell.textLabel.font = PKFont(PKFontWeightMedium, 15);
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = PKAccentColor();
        cell.textLabel.text = _loading ? PKText(@"Загрузка…") : PKText(@"Показать ещё");
        return cell;
    }
    static NSString *identifier = @"search-post";
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
    SearchViewController *next = [[[SearchViewController alloc] initWithQuery:tag] autorelease];
    [self.navigationController pushViewController:next animated:YES];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if ((NSUInteger)indexPath.row == _posts.count) { [self loadNextPage]; return; }
    StoryViewController *story = [[[StoryViewController alloc] initWithPost:[_posts objectAtIndex:indexPath.row]] autorelease];
    [self.navigationController pushViewController:story animated:YES];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    if (_posts.count && _hasMore && !_loading && scrollView.contentOffset.y + scrollView.bounds.size.height > scrollView.contentSize.height - 180)
        [self loadNextPage];
}
- (void)dealloc {
    _generation++;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_field release]; [_searchHeader release]; [_message release]; [_posts release]; [_expanded release];
    [_initialQuery release]; [_query release];
    [super dealloc];
}
@end
