#import "settings_vc.h"
#import "pk_lang.h"
#import "pk_theme.h"
#import "pk_dialog.h"
#import "pk_motion.h"
#import "about_vc.h"
#import "pk_auth.h"
#import "pk_image.h"
#import "content_settings_vc.h"
#import "pk_accent_vc.h"
#import <QuartzCore/QuartzCore.h>

@interface PKFlatSwitch : UIControl {
    UIView *_track;
    UIView *_thumb;
    BOOL _on;
}
@property(nonatomic, assign, getter=isOn) BOOL on;
@end

@implementation PKFlatSwitch
- (id)init {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 52, 44)])) {
        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
        _track = [[UIView alloc] initWithFrame:CGRectMake(0, 6, 52, 32)];
        _track.layer.cornerRadius = 16;
        _track.userInteractionEnabled = NO;
        [self addSubview:_track];
        _thumb = [[UIView alloc] initWithFrame:CGRectMake(3, 3, 26, 26)];
        _thumb.userInteractionEnabled = NO;
        _thumb.layer.cornerRadius = 13;
        _thumb.backgroundColor = [UIColor whiteColor];
        [_track addSubview:_thumb];
        PKAttachPressFeedback(self);
        [self addTarget:self action:@selector(toggle) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}
- (BOOL)isOn { return _on; }
- (void)setOn:(BOOL)on {
    _on = on;
    /* the separator color is nearly white on the light theme and hid the white knob of an off switch */
    _track.backgroundColor = on ? PKAccentFillColor() : [PKMutedColor() colorWithAlphaComponent:0.45f];
    _thumb.frame = CGRectMake(on ? 23 : 3, 3, 26, 26);
    self.accessibilityValue = on ? @"On" : @"Off";
}
- (void)toggle {
    BOOL next = !_on;
    CGFloat fromX = _thumb.layer.presentationLayer ? [(CALayer *)_thumb.layer.presentationLayer frame].origin.x : _thumb.frame.origin.x;
    CGColorRef fromColor = [(CALayer *)_track.layer.presentationLayer backgroundColor] ?: _track.layer.backgroundColor;
    self.on = next;
    if (self.window && PKMotionDuration(1) > 0) {
        PKAnimateSpring(_thumb, CGAffineTransformMakeTranslation(fromX - _thumb.frame.origin.x, 0), 1.0f, PK_SPRING_SPATIAL, 0, @"pk.thumb");
        CABasicAnimation *fade = [CABasicAnimation animationWithKeyPath:@"backgroundColor"];
        fade.fromValue = (id)fromColor;
        fade.duration = 0.18;
        [_track.layer addAnimation:fade forKey:@"pk.track"];
    }
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}
- (void)dealloc { [_track release]; [_thumb release]; [super dealloc]; }
@end

@implementation SettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = PKText(@"Настройки");
    PKStyleTable(self.tableView);
    self.tableView.rowHeight = 60.0f;
/* ios 5 and 6 paint a grouped table with a pattern view that a background color does not cover */
    self.tableView.backgroundView = nil;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:PKThemeDidChangeNotification object:nil];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)themeChanged:(NSNotification *)notification {
    (void)notification;
    self.title = PKText(@"Настройки");
    PKStyleTable(self.tableView);
    self.tableView.backgroundView = nil;
    [self.tableView reloadData];
    PKStyleNavigationBar(self.navigationController.navigationBar);
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { (void)tableView; return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { (void)tableView; return section == 0 ? 4 : ((section == 1 || section == 3) ? 2 : 1); }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    (void)tableView;
    if (section == 0) return PKText(@"ВНЕШНИЙ ВИД");
    if (section == 1) return PKText(@"ПОСТЫ И КОММЕНТАРИИ");
    return section == 2 ? PKText(@"АККАУНТ") : PKText(@"ПРИЛОЖЕНИЕ");
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { (void)tableView; (void)section; return 28.0f; }

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return PKSectionHeader([self tableView:tableView titleForHeaderInSection:section], tableView.bounds.size.width, 28.0f);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *identifier = @"settings-cell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:identifier];
    if (!cell) cell = [[[PKReadableCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier] autorelease];
    [self configureCell:cell atIndexPath:indexPath];
    return cell;
}

- (void)configureCell:(UITableViewCell *)cell atIndexPath:(NSIndexPath *)indexPath {
    cell.backgroundColor = PKCardColor();
    cell.textLabel.font = PKFont(PKFontWeightRegular, 16.0f);
    cell.textLabel.textColor = PKTextColor();
    cell.detailTextLabel.font = PKFont(PKFontWeightRegular, 12.0f);
    cell.detailTextLabel.textColor = PKMutedColor();
    cell.textLabel.shadowColor = nil;
    cell.detailTextLabel.shadowColor = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    BOOL commentsRow = indexPath.section == 1 && indexPath.row == 1;
    NSString *iconName;
    if (indexPath.section == 0) iconName = indexPath.row <= 1 ? @"theme" : (indexPath.row == 2 ? @"language" : @"feed");
    else if (indexPath.section == 1) iconName = indexPath.row == 0 ? @"feed" : @"comments";
    else if (indexPath.section == 2) iconName = @"account";
    else iconName = indexPath.row == 0 ? @"cache" : @"about";
    NSString *themeName = PKDarkThemeEnabled() ? @"dark" : @"light";
    cell.imageView.image = [UIImage imageNamed:[NSString stringWithFormat:@"Icon-settings-%@-%@.png", iconName, themeName]];
    if (commentsRow) {
        PKFlatSwitch *toggle = [cell.accessoryView isKindOfClass:[PKFlatSwitch class]] ? (PKFlatSwitch *)cell.accessoryView : nil;
        if (!toggle) {
            cell.accessoryType = UITableViewCellAccessoryNone;
            toggle = [[[PKFlatSwitch alloc] init] autorelease];
            [toggle addTarget:self action:@selector(settingChanged:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = toggle;
        }
        cell.textLabel.text = PKText(@"Сворачивать ветки");
        cell.detailTextLabel.text = PKText(@"При открытии публикации");
        toggle.on = PKCollapseCommentBranchesEnabled();
    } else {
        cell.accessoryView = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        if (indexPath.section == 0 && indexPath.row == 0) {
            cell.textLabel.text = PKText(@"Цвет темы");
            cell.detailTextLabel.text = PKDarkThemeEnabled() ? PKText(@"Тёмная") : PKText(@"Светлая");
        } else if (indexPath.section == 0 && indexPath.row == 1) {
            cell.textLabel.text = PKText(@"Цвет акцента");
            cell.detailTextLabel.text = PKText(@"Выбрать цвет");
        } else if (indexPath.section == 0 && indexPath.row == 2) {
            cell.textLabel.text = PKText(@"Язык");
            cell.detailTextLabel.text = PKLanguageName();
        } else if (indexPath.section == 0) {
            NSArray *names = [NSArray arrayWithObjects:PKText(@"Горячее"), PKText(@"Лучшее"), PKText(@"Свежее"), nil];
            cell.textLabel.text = PKText(@"Начальная лента");
            cell.detailTextLabel.text = [names objectAtIndex:(NSUInteger)PKDefaultFeedIndex()];
        } else if (indexPath.section == 1) {
            cell.textLabel.text = PKText(@"Посты и комментарии");
            cell.detailTextLabel.text = PKSessionWasAuthenticated() ? PKText(@"Настройки аккаунта") : PKText(@"Требуется вход");
        } else if (indexPath.section == 2) {
            BOOL authenticated = PKSessionWasAuthenticated();
            cell.textLabel.text = authenticated ? (PKSessionUsername() ?: PKText(@"Пользователь Weeabu")) : PKText(@"Гостевой режим");
            cell.detailTextLabel.text = authenticated ? PKText(@"Сессия активна") : PKText(@"Войти можно в разделе «Профиль»");
        } else if (indexPath.row == 0) {
            cell.textLabel.text = PKText(@"Очистить кэш");
            cell.detailTextLabel.text = PKText(@"Изображения и сетевой кэш");
        } else {
            cell.textLabel.text = PKText(@"О приложении");
            cell.detailTextLabel.text = [NSString stringWithFormat:PKText(@"Weeabu %@"),
                [[[NSBundle mainBundle] infoDictionary] objectForKey:@"GKReleaseVersion"]];
        }
        NSString *arrowName = [NSString stringWithFormat:@"Icon-settings-arrow-%@.png", themeName];
        UIImageView *arrow = [[[UIImageView alloc] initWithImage:[UIImage imageNamed:arrowName]] autorelease];
        arrow.frame = CGRectMake(0, 0, 24, 24);
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.accessoryView = arrow;
    }
}

- (void)settingChanged:(PKFlatSwitch *)toggle {
    PKSetCollapseCommentBranchesEnabled(toggle.on);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 1 && indexPath.row == 1) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        if ([cell.accessoryView isKindOfClass:[PKFlatSwitch class]]) [(PKFlatSwitch *)cell.accessoryView toggle];
    } else if (indexPath.section == 1) {
        [self.navigationController pushViewController:[[[PKContentSettingsViewController alloc] initWithStyle:UITableViewStylePlain] autorelease] animated:YES];
    } else if (indexPath.section == 2) {
        [self.navigationController.tabBarController setSelectedIndex:2];
    } else if (indexPath.section == 3 && indexPath.row == 1) {
        [self.navigationController pushViewController:[[[PKAboutViewController alloc] init] autorelease] animated:YES];
    } else if (indexPath.section == 3) {
        PKClearImageCache();
        PKShowNotice(PKText(@"Кэш очищен"), nil);
    } else if (indexPath.row == 0) {
        PKShowSheet(PKText(@"Цвет темы"), [NSArray arrayWithObjects:PKText(@"Светлая"), PKText(@"Тёмная"), nil], -1, nil, ^(NSInteger index) {
            if (index >= 0) PKSetDarkThemeEnabled(index == 1);
        });
    } else if (indexPath.row == 1) {
        [self.navigationController pushViewController:[[[PKAccentViewController alloc] init] autorelease] animated:YES];
    } else if (indexPath.row == 2) {
        PKShowSheet([NSString stringWithFormat:@"%@: %@", PKText(@"Язык"), PKLanguageName()], [NSArray arrayWithObjects:@"Русский", @"English", nil], -1, nil, ^(NSInteger index) {
            if (index >= 0) PKSetEnglishEnabled(index == 1);
        });
    } else {
        PKShowSheet(PKText(@"Начальная лента"), [NSArray arrayWithObjects:PKText(@"Горячее"), PKText(@"Лучшее"), PKText(@"Свежее"), nil], -1, nil, ^(NSInteger index) {
            if (index < 0 || index > 2) return;
            PKSetDefaultFeedIndex(index);
            [self.tableView reloadData];
        });
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}
@end
