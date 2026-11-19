#import "profile_vc.h"
#import "login_vc.h"
#import "user_lists_vc.h"
#import "pk_auth.h"
#import "pk_profile.h"
#import "pk_image.h"
#import "pk_dialog.h"
#import "pk_motion.h"
#import "pk_v1.h"
#import "pk_lang.h"
#import "pk_theme.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat PKProfileCoverHeight = 112.0f;
static const CGFloat PKProfileAvatarSide = 84.0f;

typedef enum {
    PKProfileRowPosts,
    PKProfileRowAwards,
    PKProfileRowCommunities,
    PKProfileRowSite,
    PKProfileRowCopy,
    PKProfileRowRefresh,
    PKProfileRowSignOut,
    PKProfileRowSignIn,
    PKProfileRowSubscribe,
    PKProfileRowIgnore,
    PKProfileRowMyComments,
    PKProfileRowNotifications
} PKProfileRow;

/* labels and two pictures only */
@interface PKProfileHeader : UIView {
    UIImageView *_cover;
    UIView *_scrim;
    UIImageView *_avatar;
    UILabel *_initial;
    UILabel *_name;
    UILabel *_badge;
    UILabel *_karma;
    UILabel *_votes;
    UILabel *_since;
    UILabel *_values[4];
    UILabel *_captions[4];
    NSString *_coverURL;
    NSString *_avatarURL;
    BOOL _hasStats;
}
- (void)setName:(NSString *)name badge:(NSString *)badge karma:(NSString *)karma karmaNegative:(BOOL)negative message:(NSString *)message
         profile:(PKUserProfile *)profile authenticated:(BOOL)authenticated;
- (CGFloat)heightForWidth:(CGFloat)width;
@end

@implementation PKProfileHeader

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        _cover = [[UIImageView alloc] initWithFrame:CGRectZero];
        _cover.contentMode = UIViewContentModeScaleAspectFill;
        _cover.clipsToBounds = YES;
        [self addSubview:_cover];
        _scrim = [[UIView alloc] initWithFrame:CGRectZero];
        _scrim.backgroundColor = [UIColor colorWithWhite:0 alpha:0.28f];
        [self addSubview:_scrim];
        _avatar = [[UIImageView alloc] initWithFrame:CGRectZero];
        _avatar.contentMode = UIViewContentModeScaleAspectFill;
        _avatar.clipsToBounds = YES;
        _avatar.layer.cornerRadius = PKProfileAvatarSide / 2;
        _avatar.layer.borderWidth = 3.0f;
        [self addSubview:_avatar];
        _initial = [PKLabel(30, [UIColor whiteColor], YES) retain];
        _initial.textAlignment = NSTextAlignmentCenter;
        _initial.layer.cornerRadius = PKProfileAvatarSide / 2;
        _initial.clipsToBounds = YES;
        [self addSubview:_initial];
        _name = [PKLabel(22, PKTextColor(), YES) retain]; _name.textAlignment = NSTextAlignmentCenter;
        _badge = [PKLabel(13, PKAccentColor(), YES) retain]; _badge.textAlignment = NSTextAlignmentCenter;
        _karma = [PKLabel(15, PKMutedColor(), YES) retain]; _karma.textAlignment = NSTextAlignmentCenter;
        _votes = [PKLabel(13, PKMutedColor(), NO) retain]; _votes.textAlignment = NSTextAlignmentCenter;
        _since = [PKLabel(13, PKMutedColor(), NO) retain]; _since.textAlignment = NSTextAlignmentCenter;
        for (UILabel *label in [NSArray arrayWithObjects:_name, _badge, _karma, _votes, _since, nil]) [self addSubview:label];
        NSArray *captions = [NSArray arrayWithObjects:PKText(@"постов"), PKText(@"комментариев"), PKText(@"в горячем"), PKText(@"подписчиков"), nil];
        for (int i = 0; i < 4; i++) {
            _values[i] = [PKLabel(17, PKTextColor(), YES) retain]; _values[i].textAlignment = NSTextAlignmentCenter;
            _captions[i] = [PKLabel(11, PKMutedColor(), NO) retain]; _captions[i].textAlignment = NSTextAlignmentCenter;
            _captions[i].text = [captions objectAtIndex:(NSUInteger)i];
            _captions[i].adjustsFontSizeToFitWidth = YES; _captions[i].minimumFontSize = 8;
            [self addSubview:_values[i]]; [self addSubview:_captions[i]];
        }
    }
    return self;
}

- (CGFloat)heightForWidth:(CGFloat)width {
    (void)width;
    CGFloat height = PKProfileCoverHeight + PKProfileAvatarSide / 2 + 10.0f + 28.0f;
    if (_badge.text.length) height += 20.0f;
    height += 22.0f;
    if (_votes.text.length) height += 20.0f;
    if (_since.text.length) height += 20.0f;
    if (_hasStats) height += 66.0f;
    return height + 14.0f;
}

- (void)loadImage:(NSString *)url into:(UIImageView *)view stored:(NSString **)stored {
    if ((url.length == 0 && [*stored length] == 0) || [url isEqualToString:*stored]) return;
    [*stored release]; *stored = [url copy];
    view.image = nil;
    if (!url.length) return;
    NSString *requested = [[url copy] autorelease];
    PKLoadImage(requested, ^(UIImage *image) {
        if (![requested isEqualToString:*stored]) return;
        view.image = image;
        /* the layout pass hides the letter and a late picture does not trigger one, so the letter stayed over it */
        [self setNeedsLayout];
    });
}

- (void)setName:(NSString *)name badge:(NSString *)badge karma:(NSString *)karma karmaNegative:(BOOL)negative message:(NSString *)message
         profile:(PKUserProfile *)profile authenticated:(BOOL)authenticated {
    self.backgroundColor = PKCardColor();
    _cover.backgroundColor = [PKAccentFillColor() colorWithAlphaComponent:0.45f];
    _avatar.layer.borderColor = PKCardColor().CGColor;
    _avatar.backgroundColor = PKControlColor();
    _initial.backgroundColor = authenticated || profile ? PKAccentFillColor() : PKControlColor();
    _initial.textColor = authenticated || profile ? [UIColor whiteColor] : PKMutedColor();
    _initial.text = name.length ? [[name substringToIndex:1] uppercaseString] : @"?";
    _name.text = name; _name.textColor = PKTextColor();
    _badge.text = badge; _badge.textColor = PKAccentColor();
    _karma.text = karma; _karma.textColor = negative ? PKDangerColor() : PKMutedColor();
    _hasStats = profile != nil;
    NSMutableString *since = [NSMutableString string];
    if (profile.registration.length) [since appendFormat:PKText(@"На Пикабу: %@"), profile.registration];
    _since.text = since.length ? since : message;
    _since.textColor = PKMutedColor();
    _votes.text = profile ? [NSString stringWithFormat:@"+%@  /  −%@", PKCompactScore(profile.pluses), PKCompactScore(profile.minuses)] : @"";
    _votes.textColor = PKMutedColor();
    NSInteger numbers[4] = { profile.stories, profile.comments, profile.hotStories, profile.subscribers };
    for (int i = 0; i < 4; i++) {
        _values[i].text = PKCompactScore(numbers[i]); _values[i].textColor = PKTextColor();
        _captions[i].textColor = PKMutedColor();
        _values[i].hidden = _captions[i].hidden = !_hasStats;
    }
    _cover.hidden = _scrim.hidden = !profile;
    [self loadImage:profile.headerURL into:_cover stored:&_coverURL];
    [self loadImage:profile.avatarURL into:_avatar stored:&_avatarURL];
    _initial.hidden = _avatar.image != nil;
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    _cover.frame = CGRectMake(0, 0, width, PKProfileCoverHeight);
    _scrim.frame = _cover.frame;
    CGRect avatar = CGRectMake(floorf((width - PKProfileAvatarSide) / 2), PKProfileCoverHeight - PKProfileAvatarSide / 2, PKProfileAvatarSide, PKProfileAvatarSide);
    if (!_hasStats && _cover.hidden) avatar.origin.y = 18.0f;
    _avatar.frame = avatar;
    _initial.frame = avatar;
    _initial.hidden = _avatar.image != nil;
    CGFloat y = avatar.origin.y + PKProfileAvatarSide + 10.0f;
    CGFloat inner = PKContentWidth(width) - 32.0f;
    CGFloat left = PKContentSideInset(width) + 16.0f;
    _name.frame = CGRectMake(left, y, inner, 28); y += 28;
    if (_badge.text.length) { _badge.frame = CGRectMake(left, y, inner, 18); y += 20; } else _badge.frame = CGRectZero;
    _karma.frame = CGRectMake(left, y, inner, 20); y += 22;
    if (_votes.text.length) { _votes.frame = CGRectMake(left, y, inner, 18); y += 20; } else _votes.frame = CGRectZero;
    if (_since.text.length) { _since.frame = CGRectMake(left, y, inner, 18); y += 20; } else _since.frame = CGRectZero;
    if (_hasStats) {
        y += 8;
        CGFloat column = inner / 4;
        for (int i = 0; i < 4; i++) {
            _values[i].frame = CGRectMake(left + column * i, y, column, 24);
            _captions[i].frame = CGRectMake(left + column * i + 2, y + 24, column - 4, 16);
        }
    }
}

- (void)dealloc {
    [_cover release]; [_scrim release]; [_avatar release]; [_initial release]; [_name release]; [_badge release]; [_karma release]; [_votes release]; [_since release];
    for (int i = 0; i < 4; i++) { [_values[i] release]; [_captions[i] release]; }
    [_coverURL release]; [_avatarURL release];
    [super dealloc];
}
@end

@interface ProfileViewController () {
    NSString *_username;
    BOOL _own;
    BOOL _authenticated;
    BOOL _checking;
    BOOL _signingOut;
    BOOL _loading;
    BOOL _busy;
    NSUInteger _generation;
    PKUserProfile *_profile;
    NSError *_loadError;
    PKProfileHeader *_header;
    NSArray *_rows;
}
@end

@implementation ProfileViewController

- (id)initWithStyle:(UITableViewStyle)style {
    (void)style;
    return [self initWithUsername:nil];
}
- (id)initWithUsername:(NSString *)username {
    if ((self = [super initWithStyle:UITableViewStylePlain])) {
        _own = username.length == 0;
        _username = [username copy];
    }
    return self;
}

- (NSString *)shownName {
    return _own ? (_authenticated ? PKSessionUsername() : nil) : _username;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = _own ? PKText(@"Профиль") : _username;
    self.tableView.backgroundView = nil;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _header = [[PKProfileHeader alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 220)];
    _header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.tableView.tableHeaderView = _header;
    _authenticated = PKSessionWasAuthenticated();
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:PKThemeDidChangeNotification object:nil];
    [self rebuild];
    if (_own) [self checkSession]; else [self loadProfile];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (_own) {
        BOOL was = _authenticated;
        _authenticated = PKSessionWasAuthenticated();
        if (was != _authenticated) { if (_authenticated) [self loadProfile]; else [self dropProfile]; }
    }
    [self rebuild];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutHeader];
}
- (void)layoutHeader {
    CGFloat width = self.tableView.bounds.size.width;
    if (width <= 0) return;
    CGFloat height = [_header heightForWidth:width];
    if (fabsf((float)(_header.frame.size.height - height)) > 0.5f || fabsf((float)(_header.frame.size.width - width)) > 0.5f) {
        _header.frame = CGRectMake(0, 0, width, height);
        self.tableView.tableHeaderView = _header;
    }
}
- (void)themeChanged:(NSNotification *)note {
    (void)note;
    self.title = _own ? PKText(@"Профиль") : _username;
    [self rebuild];
}

- (void)dropProfile {
    _generation++;
    [_profile release]; _profile = nil;
    [_loadError release]; _loadError = nil;
    _loading = NO;
}

- (void)loadProfile {
    NSString *name = [self shownName];
    if (!name.length) { [self dropProfile]; [self rebuild]; return; }
    NSUInteger generation = ++_generation;
    _loading = YES;
    [_loadError release]; _loadError = nil;
    [self rebuild];
    PKLoadUserProfile(name, ^(PKUserProfile *profile, NSError *error) {
        if (generation != _generation) return;
        _loading = NO;
        if (error) { _loadError = [error retain]; }
        else { [_profile release]; _profile = [profile retain]; }
        [self rebuild];
    });
}

- (void)checkSession {
    if (_checking) return;
    _checking = YES;
    PKCheckSession(^(BOOL authenticated, NSString *username, NSError *error) {
        (void)username;
        _checking = NO;
        if (!error) {
            BOOL was = _authenticated;
            _authenticated = authenticated;
            if (authenticated) { [self loadProfile]; return; }
            if (was) [self dropProfile];
        }
        [self rebuild];
    });
}

- (void)rebuild {
    NSMutableArray *rows = [NSMutableArray array];
    BOOL someoneElse = _profile && !_own && [_profile.name caseInsensitiveCompare:PKSessionUsername() ?: @""] != NSOrderedSame;
    if (someoneElse) [rows addObject:[NSNumber numberWithInt:PKProfileRowSubscribe]];
    if (_profile) {
        [rows addObject:[NSNumber numberWithInt:PKProfileRowPosts]];
        [rows addObject:[NSNumber numberWithInt:PKProfileRowAwards]];
        [rows addObject:[NSNumber numberWithInt:PKProfileRowCommunities]];
        if (_own && _authenticated) {
            [rows addObject:[NSNumber numberWithInt:PKProfileRowMyComments]];
            [rows addObject:[NSNumber numberWithInt:PKProfileRowNotifications]];
        }
        [rows addObject:[NSNumber numberWithInt:PKProfileRowSite]];
        [rows addObject:[NSNumber numberWithInt:PKProfileRowCopy]];
        if (someoneElse) [rows addObject:[NSNumber numberWithInt:PKProfileRowIgnore]];
    }
    if (_own) {
        if (_authenticated) {
            [rows addObject:[NSNumber numberWithInt:PKProfileRowRefresh]];
            [rows addObject:[NSNumber numberWithInt:PKProfileRowSignOut]];
        } else {
            [rows addObject:[NSNumber numberWithInt:PKProfileRowSignIn]];
            [rows addObject:[NSNumber numberWithInt:PKProfileRowSite]];
        }
    }
    [_rows release]; _rows = [rows copy];

    NSString *name = _profile.name ?: [self shownName];
    NSString *message = nil;
    NSString *karma = nil;
    if (_own && !_authenticated) {
        name = PKText(@"Гостевой режим");
        message = PKText(@"Лента и комментарии доступны без входа");
    } else if (_loading) {
        message = PKText(@"Загружаем профиль…");
    } else if (_loadError) {
        message = PKText(@"Не удалось загрузить профиль");
    } else if (!_profile) {
        message = PKText(@"Сессия активна");
    }
    if (_profile.rating.length) karma = [NSString stringWithFormat:PKText(@"Рейтинг: %@"), _profile.rating];
    self.tableView.backgroundColor = PKBackgroundColor();
    [_header setName:name badge:_profile.approved karma:karma karmaNegative:_profile.ratingNegative message:message profile:_profile authenticated:_authenticated];
    [self layoutHeader];
    [self.tableView reloadData];
}

#pragma mark table

- (BOOL)hasAbout { return _profile.about.length > 0; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return [self hasAbout] ? 2 : 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    if ([self hasAbout] && section == 0) return 1;
    return (NSInteger)_rows.count;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self hasAbout] && indexPath.section == 0) {
        CGFloat width = PKContentWidth(tableView.bounds.size.width) - 32.0f;
        CGSize fit = [_profile.about sizeWithFont:PKFont(PKFontWeightRegular, 15) constrainedToSize:CGSizeMake(width, 4000) lineBreakMode:NSLineBreakByWordWrapping];
        return MAX(48.0f, ceilf(fit.height) + 28.0f);
    }
    return 56.0f;
}
/* UITableViewHeaderFooterView does not exist before ios 6 */
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    (void)tableView;
    return [self hasAbout] && section == 0 ? 34.0f : 12.0f;
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    BOOL about = [self hasAbout] && section == 0;
    UIView *view = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, about ? 34 : 12)] autorelease];
    view.backgroundColor = PKBackgroundColor();
    if (about) {
        UILabel *label = PKLabel(12, PKMutedColor(), YES);
        label.text = PKText(@"О СЕБЕ");
        CGFloat side = PKContentSideInset(tableView.bounds.size.width);
        label.frame = CGRectMake(side + 16, 12, PKContentWidth(tableView.bounds.size.width) - 32, 16);
        label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [view addSubview:label];
    }
    return view;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([self hasAbout] && indexPath.section == 0) {
        static NSString *identifier = @"profile-about";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
        if (!cell) cell = [[[PKReadableCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier] autorelease];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        cell.backgroundColor = PKCardColor();
        cell.textLabel.numberOfLines = 0;
        cell.textLabel.font = PKFont(PKFontWeightRegular, 15);
        cell.textLabel.textColor = PKTextColor();
        cell.textLabel.text = _profile.about;
        cell.accessoryType = UITableViewCellAccessoryNone;
        return cell;
    }
    static NSString *identifier = @"profile-action";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[PKReadableCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:identifier] autorelease];
    PKProfileRow row = (PKProfileRow)[[_rows objectAtIndex:(NSUInteger)indexPath.row] intValue];
    cell.selectionStyle = UITableViewCellSelectionStyleGray;
    cell.backgroundColor = PKCardColor();
    cell.textLabel.numberOfLines = 1;
    cell.textLabel.font = PKFont(PKFontWeightMedium, 16);
    cell.textLabel.textColor = row == PKProfileRowSignOut ? PKDangerColor() : PKTextColor();
    cell.detailTextLabel.font = PKFont(PKFontWeightRegular, 15);
    cell.detailTextLabel.textColor = PKMutedColor();
    NSString *title = nil, *detail = nil;
    switch (row) {
        case PKProfileRowPosts: title = PKText(@"Посты автора"); detail = PKCompactScore(_profile.stories); break;
        case PKProfileRowAwards: title = PKText(@"Награды"); detail = PKCompactScore((NSInteger)_profile.awards.count); break;
        case PKProfileRowCommunities: title = PKText(@"Сообщества"); detail = PKCompactScore((NSInteger)_profile.communities.count); break;
        case PKProfileRowSite: title = PKText(@"Открыть на сайте"); break;
        case PKProfileRowCopy: title = PKText(@"Скопировать ссылку на профиль"); break;
        case PKProfileRowRefresh: title = PKText(@"Обновить"); break;
        case PKProfileRowSignOut: title = PKText(@"Выйти"); break;
        case PKProfileRowSignIn: title = PKText(@"Войти"); break;
        case PKProfileRowSubscribe: title = _profile.subscribed ? PKText(@"Отписаться") : PKText(@"Подписаться"); detail = _busy ? @"…" : nil; break;
        case PKProfileRowIgnore: title = _profile.ignored ? PKText(@"Перестать игнорировать") : PKText(@"Игнорировать автора"); detail = _busy ? @"…" : nil; break;
        case PKProfileRowMyComments: title = PKText(@"Мои комментарии"); break;
        case PKProfileRowNotifications: title = PKText(@"Уведомления"); break;
    }
    if (row == PKProfileRowSubscribe && !_profile.subscribed) cell.textLabel.textColor = PKAccentColor();
    if (row == PKProfileRowIgnore && !_profile.ignored) cell.textLabel.textColor = PKDangerColor();
    cell.textLabel.text = title;
    cell.detailTextLabel.text = detail;
    BOOL disclosure = row == PKProfileRowMyComments || row == PKProfileRowNotifications || row == PKProfileRowPosts || row == PKProfileRowAwards || row == PKProfileRowCommunities || row == PKProfileRowSignIn || row == PKProfileRowSite;
    cell.accessoryType = disclosure ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    if (row == PKProfileRowAwards && !_profile.awards.count) cell.accessoryType = UITableViewCellAccessoryNone;
    if (row == PKProfileRowCommunities && !_profile.communities.count) cell.accessoryType = UITableViewCellAccessoryNone;
    return cell;
}

- (void)signOut {
    if (_signingOut) return;
    _signingOut = YES;
    PKSignOut(^(NSError *error) {
        _signingOut = NO;
        _authenticated = NO;
        [self dropProfile];
        [self rebuild];
        if (error)
            PKShowNotice(PKText(@"Выход"), [NSString stringWithFormat:PKText(@"Вы вышли на этом устройстве, но сайт не подтвердил выход: %@"), error.localizedDescription]);
    });
}

/* an account that signed in before the api session existed has to open it with its password */
- (void)changeState:(BOOL)subscribe {
    if (_busy || !_profile) return;
    if (!PKSessionWasAuthenticated()) { [self pushLogin]; return; }
    PKUserProfile *profile = [[_profile retain] autorelease];
    BOOL target = subscribe ? !profile.subscribed : !profile.ignored;
    _busy = YES;
    [self.tableView reloadData];
    void (^finish)(NSError *) = ^(NSError *error) {
        _busy = NO;
        if (PKV1IsUnauthorized(error)) {
            PKPromptApiSession(^(BOOL opened) { [self.tableView reloadData]; if (opened) [self changeState:subscribe]; });
            return;
        }
        if (error) {
            PKShowNotice(subscribe ? PKText(@"Не удалось изменить подписку") : PKText(@"Не удалось изменить игнор"), error.localizedDescription);
        } else if (subscribe) {
            profile.subscribed = target;
            profile.subscribers = MAX(0, profile.subscribers + (target ? 1 : -1));
        } else {
            profile.ignored = target;
        }
        if (profile == _profile) [self rebuild]; else [self.tableView reloadData];
    };
    if (subscribe) PKSetSubscribed(profile.userID, target, finish);
    else PKSetIgnored(profile.userID, target, finish);
}

- (void)pushLogin {
    PKLoginViewController *login = [[[PKLoginViewController alloc] initWithCompletion:^(BOOL authenticated) {
        _authenticated = authenticated;
        if (_own) { if (authenticated) [self loadProfile]; else [self rebuild]; } else [self rebuild];
    }] autorelease];
    [self.navigationController pushViewController:login animated:YES];
}

- (void)openSite {
    NSString *url = _profile ? [_profile pageURL] : @"https://pikabu.ru/";
    NSURL *target = [NSURL URLWithString:url];
    if (target) [[UIApplication sharedApplication] openURL:target];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([self hasAbout] && indexPath.section == 0) return;
    PKProfileRow row = (PKProfileRow)[[_rows objectAtIndex:(NSUInteger)indexPath.row] intValue];
    NSString *name = _profile.name;
    switch (row) {
        case PKProfileRowPosts:
            [self.navigationController pushViewController:[[[PKUserPostsViewController alloc] initWithUsername:name] autorelease] animated:YES];
            break;
        case PKProfileRowAwards:
            if (_profile.awards.count) [self.navigationController pushViewController:[[[PKAwardsViewController alloc] initWithAwards:_profile.awards name:name] autorelease] animated:YES];
            break;
        case PKProfileRowCommunities:
            if (_profile.communities.count) [self.navigationController pushViewController:[[[PKCommunitiesViewController alloc] initWithCommunities:_profile.communities name:name] autorelease] animated:YES];
            break;
        case PKProfileRowSite: [self openSite]; break;
        case PKProfileRowCopy:
            [UIPasteboard generalPasteboard].string = [_profile pageURL];
            PKShowNotice(nil, PKText(@"Ссылка скопирована"));
            break;
        case PKProfileRowRefresh: [self checkSession]; break;
        case PKProfileRowSignOut:
            PKShowAlert(PKText(@"Выйти из аккаунта?"), nil, [NSArray arrayWithObjects:PKText(@"Отмена"), PKText(@"Выйти"), nil], 1, YES, ^(NSInteger index) {
                if (index == 1) [self signOut];
            });
            break;
        case PKProfileRowSignIn: [self pushLogin]; break;
        case PKProfileRowSubscribe: [self changeState:YES]; break;
        case PKProfileRowIgnore: [self changeState:NO]; break;
        case PKProfileRowMyComments:
            [self.navigationController pushViewController:[[[PKMyCommentsViewController alloc] initWithStyle:UITableViewStylePlain] autorelease] animated:YES];
            break;
        case PKProfileRowNotifications:
            [self.navigationController pushViewController:[[[PKNotificationsViewController alloc] initWithStyle:UITableViewStylePlain] autorelease] animated:YES];
            break;
    }
}

- (void)dealloc {
    _generation++;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_username release]; [_profile release]; [_loadError release]; [_header release]; [_rows release];
    [super dealloc];
}
@end
