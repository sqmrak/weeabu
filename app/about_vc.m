#import "about_vc.h"
#import "pk_lang.h"
#import "pk_theme.h"
#import "pk_auth.h"
#import <QuartzCore/QuartzCore.h>
#include <sys/sysctl.h>
#include "pk_device.h"

static NSString * const kAboutTitle = @"t";
static NSString * const kAboutValue = @"v";
static NSString * const kAboutImage = @"i";
static NSString * const kAboutAction = @"a";

enum { kAboutHeroHeight = 262 };

/* keeps ipad landscape rows from stretching across the screen */
static CGFloat AboutSideMargin(CGFloat width) {
    CGFloat margin = floorf((width - 700.0f) * 0.5f);
    return margin > 12.0f ? margin : 12.0f;
}

/* ios 5 and 6 inset grouped rows themselves, ios 7 runs them edge to edge */
static BOOL AboutRowsInsetBySystem(void) {
    return ![UITableView instancesRespondToSelector:@selector(setSeparatorInset:)];
}

static CGFloat AboutRowInset(CGFloat width) {
    if (!AboutRowsInsetBySystem()) return AboutSideMargin(width);
    return [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad ? 45.0f : 10.0f;
}

static NSString *AboutModel(void) {
    char machine[64];
    size_t length = sizeof machine;
    if (sysctlbyname("hw.machine", machine, &length, NULL, 0) != 0 || length == 0 || length > sizeof machine)
        return [[UIDevice currentDevice] model];
    machine[sizeof machine - 1] = '\0';
    const char *name = pk_device_name(machine);
    if (name) return [NSString stringWithUTF8String:name];
    return [[UIDevice currentDevice] model];
}

static NSString *AboutSlice(void) {
#if defined(__arm64__) || defined(__aarch64__)
    return @"arm64";
#else
    return @"armv7";
#endif
}

static NSString *AboutVersion(void) {
    NSString *version = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"GKReleaseVersion"];
    return [version length] ? version : @"1.0.0";
}

/* only the first row rounds its top and only the last its bottom */
@interface PKAboutPlate : UIView {
    UIRectCorner _corners;
}
- (id)initWithCorners:(UIRectCorner)corners;
@end

@implementation PKAboutPlate
- (id)initWithCorners:(UIRectCorner)corners {
    if ((self = [super initWithFrame:CGRectZero])) {
        _corners = corners;
        self.opaque = NO;
        self.backgroundColor = [UIColor clearColor];
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}
- (void)drawRect:(CGRect)rect {
    (void)rect;
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:self.bounds
                                               byRoundingCorners:_corners
                                                     cornerRadii:CGSizeMake(14.0f, 14.0f)];
    [PKCardColor() setFill];
    [path fill];
    if (!(_corners & UIRectCornerBottomLeft)) {
        [PKSeparatorColor() setFill];
        UIRectFill(CGRectMake(16.0f, self.bounds.size.height - 1.0f, self.bounds.size.width - 16.0f, 1.0f));
    }
}
@end

@interface PKAboutCell : UITableViewCell {
@public
    UIImageView *icon;
    UILabel *titleLabel;
    UILabel *valueLabel;
}
@end

@implementation PKAboutCell
- (id)initWithReuseIdentifier:(NSString *)identifier {
    if ((self = [super initWithStyle:UITableViewCellStyleDefault reuseIdentifier:identifier])) {
        self.backgroundColor = [UIColor clearColor];
        icon = [[UIImageView alloc] initWithFrame:CGRectZero];
        icon.contentMode = UIViewContentModeScaleAspectFill;
        icon.clipsToBounds = YES;
        [self.contentView addSubview:icon];
        titleLabel = [PKLabel(15, PKTextColor(), YES) retain];
        titleLabel.lineBreakMode = NSLineBreakByTruncatingTail;
        [self.contentView addSubview:titleLabel];
        valueLabel = [PKLabel(14, PKMutedColor(), NO) retain];
        valueLabel.numberOfLines = 0;
        valueLabel.lineBreakMode = NSLineBreakByWordWrapping;
        [self.contentView addSubview:valueLabel];
    }
    return self;
}
- (void)dealloc {
    [icon release]; [titleLabel release]; [valueLabel release];
    [super dealloc];
}
/* ios 7 draws grouped rows edge to edge, so the plates bring their own margin */
- (void)setFrame:(CGRect)frame {
    if (!AboutRowsInsetBySystem() && frame.origin.x < 1.0f)
        frame = CGRectInset(frame, AboutSideMargin(frame.size.width), 0.0f);
    [super setFrame:frame];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.contentView.bounds;
    CGFloat x = 16.0f;
    if (icon.image) {
        icon.frame = CGRectMake(16.0f, 14.0f, 24.0f, 24.0f);
        icon.layer.cornerRadius = 12.0f;
        x = 52.0f;
    } else {
        icon.frame = CGRectZero;
    }
    CGFloat width = MAX(40.0f, bounds.size.width - x - 12.0f);
    titleLabel.frame = CGRectMake(x, 12.0f, width, 20.0f);
    CGFloat valueHeight = bounds.size.height - 36.0f - 10.0f;
    valueLabel.frame = CGRectMake(x, 34.0f, width, valueHeight > 0.0f ? valueHeight : 0.0f);
}
@end

@interface PKAboutHero : UIView {
@public
    UIImageView *icon;
    UILabel *name;
    UILabel *tagline;
    UIView *versionTile;
    UIView *systemTile;
    UILabel *versionCaption;
    UILabel *versionValue;
    UILabel *systemCaption;
    UILabel *systemValue;
}
- (void)applyTheme;
@end

static UILabel *AboutHeroLabel(UIView *host, UIFont *font) {
    UILabel *label = [[[UILabel alloc] initWithFrame:CGRectZero] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.font = font;
    label.textAlignment = NSTextAlignmentCenter;
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.adjustsFontSizeToFitWidth = YES;
    [host addSubview:label];
    return label;
}

@implementation PKAboutHero
- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.backgroundColor = [UIColor clearColor];
        icon = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"Icon-60@2x.png"]];
        icon.contentMode = UIViewContentModeScaleAspectFill;
        icon.clipsToBounds = YES;
        icon.layer.cornerRadius = 19.0f;
        [self addSubview:icon];
        name = [AboutHeroLabel(self, PKFont(PKFontWeightBold, 30.0f)) retain];
        name.text = PKText(@"Weeabu");
        tagline = [AboutHeroLabel(self, PKFont(PKFontWeightRegular, 14.0f)) retain];
        versionTile = [[UIView alloc] initWithFrame:CGRectZero];
        systemTile = [[UIView alloc] initWithFrame:CGRectZero];
        versionTile.layer.cornerRadius = 14.0f;
        systemTile.layer.cornerRadius = 14.0f;
        [self addSubview:versionTile];
        [self addSubview:systemTile];
        versionCaption = [AboutHeroLabel(versionTile, PKFont(PKFontWeightRegular, 12.0f)) retain];
        versionValue = [AboutHeroLabel(versionTile, PKFont(PKFontWeightMedium, 17.0f)) retain];
        systemCaption = [AboutHeroLabel(systemTile, PKFont(PKFontWeightRegular, 12.0f)) retain];
        systemValue = [AboutHeroLabel(systemTile, PKFont(PKFontWeightMedium, 17.0f)) retain];
        versionValue.text = AboutVersion();
        systemCaption.text = @"iOS";
        systemValue.text = [NSString stringWithFormat:@"%@ · %@",
                            [[UIDevice currentDevice] systemVersion], AboutSlice()];
    }
    return self;
}
- (void)dealloc {
    [icon release]; [name release]; [tagline release]; [versionTile release]; [systemTile release];
    [versionCaption release]; [versionValue release]; [systemCaption release]; [systemValue release];
    [super dealloc];
}
- (void)applyTheme {
    name.textColor = PKTextColor();
    tagline.textColor = PKMutedColor();
    versionCaption.textColor = PKMutedColor();
    systemCaption.textColor = PKMutedColor();
    versionValue.textColor = PKTextColor();
    systemValue.textColor = PKTextColor();
    versionTile.backgroundColor = PKCardColor();
    systemTile.backgroundColor = PKCardColor();
    tagline.text = PKText(@"Нативный клиент Пикабу для iOS");
    versionCaption.text = PKText(@"Версия");
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width;
    CGFloat side = AboutRowInset(width);
    icon.frame = CGRectMake(floorf((width - 88.0f) * 0.5f), 22.0f, 88.0f, 88.0f);
    name.frame = CGRectMake(side, 118.0f, width - side * 2.0f, 38.0f);
    tagline.frame = CGRectMake(side, 156.0f, width - side * 2.0f, 18.0f);
    CGFloat gap = 10.0f;
    CGFloat tileWidth = floorf((width - side * 2.0f - gap) * 0.5f);
    versionTile.frame = CGRectMake(side, 188.0f, tileWidth, 66.0f);
    systemTile.frame = CGRectMake(width - side - tileWidth, 188.0f, tileWidth, 66.0f);
    versionCaption.frame = CGRectMake(8.0f, 11.0f, tileWidth - 16.0f, 16.0f);
    versionValue.frame = CGRectMake(8.0f, 29.0f, tileWidth - 16.0f, 24.0f);
    systemCaption.frame = versionCaption.frame;
    systemValue.frame = versionValue.frame;
}
@end

@interface PKAboutViewController () <UITableViewDataSource, UITableViewDelegate> {
    UITableView *_table;
    PKAboutHero *_hero;
    NSArray *_sections;
}
@end

@implementation PKAboutViewController

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _table.dataSource = nil;
    _table.delegate = nil;
    [_table release]; [_hero release]; [_sections release];
    [super dealloc];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    CGRect bounds = self.view.bounds;
    _table = [[UITableView alloc] initWithFrame:bounds style:UITableViewStyleGrouped];
    _table.dataSource = self;
    _table.delegate = self;
    _table.separatorStyle = UITableViewCellSeparatorStyleNone;
    _table.backgroundColor = [UIColor clearColor];
/* ios 5 and 6 paint a grouped table with a pattern view */
    _table.backgroundView = nil;
    _table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_table];

    _hero = [[PKAboutHero alloc] initWithFrame:CGRectMake(0, 0, bounds.size.width, kAboutHeroHeight)];
    _table.tableHeaderView = _hero;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:PKThemeDidChangeNotification object:nil];
    [self applyTheme];
}

- (void)applyTheme {
    self.title = PKText(@"О приложении");
    self.view.backgroundColor = PKBackgroundColor();
    [_hero applyTheme];
    [self rebuildRows];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    _table.frame = bounds;
/* uitableview rereads the header height only when the view is set again */
    if (fabsf((float)(_hero.frame.size.width - bounds.size.width)) > 0.5f) {
        _hero.frame = CGRectMake(0, 0, bounds.size.width, kAboutHeroHeight);
        _table.tableHeaderView = _hero;
        [_table reloadData];
    }
}

- (NSDictionary *)row:(NSString *)title value:(NSString *)value action:(SEL)action {
    NSMutableDictionary *row = [NSMutableDictionary dictionaryWithCapacity:4];
    [row setObject:PKText(title) forKey:kAboutTitle];
    [row setObject:value ?: @"" forKey:kAboutValue];
    if (action) [row setObject:NSStringFromSelector(action) forKey:kAboutAction];
    return row;
}

- (NSDictionary *)section:(NSString *)title rows:(NSArray *)rows {
    return [NSDictionary dictionaryWithObjectsAndKeys:PKText(title), kAboutTitle, rows, kAboutValue, nil];
}

- (void)rebuildRows {
    NSMutableDictionary *developer = [NSMutableDictionary dictionaryWithDictionary:
                                      [self row:@"Разработчик" value:@"sqmrak" action:NULL]];
    UIImage *face = [UIImage imageNamed:@"sqmrak.jpg"];
    if (face) [developer setObject:face forKey:kAboutImage];

    NSString *account = PKSessionWasAuthenticated()
        ? [NSString stringWithFormat:PKText(@"Вы вошли как %@"), PKSessionUsername() ?: PKText(@"Пользователь Weeabu")]
        : PKText(@"Лента и комментарии доступны без входа. Войти можно по логину и паролю.");

    NSArray *sections = [NSArray arrayWithObjects:
        [self section:@"Устройство" rows:[NSArray arrayWithObjects:
            [self row:@"Модель" value:AboutModel() action:NULL],
            [self row:@"iOS" value:[[UIDevice currentDevice] systemVersion] action:NULL],
            [self row:@"Архитектура" value:AboutSlice() action:NULL],
            nil]],
        [self section:@"Weeabu" rows:[NSArray arrayWithObjects:
            [self row:@"Что работает" value:PKText(@"Горячее, лучшее и свежее, поиск, посты, комментарии, реакции, картинки, гифки и видео без веб-страницы внутри.") action:NULL],
            [self row:@"Аккаунт" value:account action:NULL],
            [self row:@"Совместимость" value:@"iOS 5+ · armv7 + arm64" action:NULL],
            [self row:@"Сеть" value:PKText(@"Собственный TLS-слой для старых систем. Пароль уходит только на pikabu.ru и нигде не сохраняется.") action:NULL],
            nil]],
        [self section:@"Ссылки" rows:[NSArray arrayWithObjects:
            [self row:@"GitHub" value:@"github.com/sqmrak" action:@selector(openGithub)],
            [self row:@"Telegram" value:@"t.me/sqmrakdev" action:@selector(openTelegram)],
            nil]],
        [self section:@"Авторы" rows:[NSArray arrayWithObjects:
            developer,
            [self row:@"Тестер" value:@"@not_a_modder" action:NULL],
            [self row:@"Отказ от ответственности" value:PKText(@"Неофициальный клиент сайта pikabu.ru.") action:NULL],
            nil]],
        nil];
    [_sections release];
    _sections = [sections retain];
    [_table reloadData];
}

- (NSDictionary *)rowAtIndexPath:(NSIndexPath *)indexPath {
    NSArray *rows = [[_sections objectAtIndex:(NSUInteger)indexPath.section] objectForKey:kAboutValue];
    return [rows objectAtIndex:(NSUInteger)indexPath.row];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return (NSInteger)_sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    (void)tableView;
    return (NSInteger)[[[_sections objectAtIndex:(NSUInteger)section] objectForKey:kAboutValue] count];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *row = [self rowAtIndexPath:indexPath];
    NSString *value = [row objectForKey:kAboutValue];
    if (![value length]) return 52.0f;
    BOOL leading = [row objectForKey:kAboutImage] != nil;
    CGFloat width = tableView.bounds.size.width - AboutRowInset(tableView.bounds.size.width) * 2.0f -
                    (leading ? 52.0f : 16.0f) - 12.0f -
                    ([row objectForKey:kAboutAction] ? 34.0f : 0.0f);
    if (width < 40.0f) width = 40.0f;
    CGSize size = [value sizeWithFont:PKFont(PKFontWeightRegular, 14.0f)
                    constrainedToSize:CGSizeMake(width, 10000.0f)
                        lineBreakMode:NSLineBreakByWordWrapping];
    return MAX(56.0f, ceilf(size.height) + 36.0f + 12.0f);
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { (void)tableView; (void)section; return 36.0f; }
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section { (void)tableView; (void)section; return 4.0f; }

/* ios 7 restyles the stock header label */
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    CGFloat width = tableView.bounds.size.width;
    UIView *wrap = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 36.0f)] autorelease];
    wrap.backgroundColor = [UIColor clearColor];
    CGFloat x = AboutRowInset(width) + 16.0f;
    UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(x, 12.0f, width - x * 2.0f, 20.0f)] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.font = PKFont(PKFontWeightMedium, 13.0f);
    label.textColor = PKSectionTitleColor();
    label.text = [[_sections objectAtIndex:(NSUInteger)section] objectForKey:kAboutTitle];
    [wrap addSubview:label];
    return wrap;
}

- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section {
    (void)tableView; (void)section;
    return [[[UIView alloc] initWithFrame:CGRectZero] autorelease];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"about";
    PKAboutCell *cell = (PKAboutCell *)[tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[PKAboutCell alloc] initWithReuseIdentifier:identifier] autorelease];
    NSDictionary *row = [self rowAtIndexPath:indexPath];
    BOOL tappable = [row objectForKey:kAboutAction] != nil;
    NSInteger count = [self tableView:tableView numberOfRowsInSection:indexPath.section];
    UIRectCorner corners = 0;
    if (indexPath.row == 0) corners |= UIRectCornerTopLeft | UIRectCornerTopRight;
    if (indexPath.row == count - 1) corners |= UIRectCornerBottomLeft | UIRectCornerBottomRight;
    cell.backgroundView = [[[PKAboutPlate alloc] initWithCorners:corners] autorelease];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.accessoryType = tappable ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;
    cell->titleLabel.textColor = PKTextColor();
    cell->titleLabel.text = [row objectForKey:kAboutTitle];
    cell->valueLabel.textColor = PKMutedColor();
    cell->valueLabel.text = [row objectForKey:kAboutValue];
    cell->icon.image = [row objectForKey:kAboutImage];
    [cell setNeedsLayout];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *action = [[self rowAtIndexPath:indexPath] objectForKey:kAboutAction];
    if ([action length]) [self performSelector:NSSelectorFromString(action)];
}

- (void)openGithub {
    NSURL *url = [NSURL URLWithString:@"https://github.com/sqmrak"];
    if (url) [[UIApplication sharedApplication] openURL:url];
}

- (void)openTelegram {
    NSURL *url = [NSURL URLWithString:@"https://t.me/sqmrakdev"];
    if (url) [[UIApplication sharedApplication] openURL:url];
}

@end
