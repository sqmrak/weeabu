#import "main_vc.h"
#import "pk_lang.h"
#import "feed_vc.h"
#import "search_vc.h"
#import "profile_vc.h"
#import "settings_vc.h"
#import "pk_theme.h"
#import "pk_motion.h"
#import "pk_icons.h"
#import <math.h>

static UIImage *PKTintTabIcon(UIImage *image, UIColor *color) {
    if (!image) return nil;
    UIGraphicsBeginImageContextWithOptions(image.size, NO, image.scale);
    CGRect rect = CGRectMake(0, 0, image.size.width, image.size.height);
    [image drawInRect:rect];
    [color setFill];
    UIRectFillUsingBlendMode(rect, kCGBlendModeSourceIn);
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

static void PKApplyTabIcons(UITabBarItem *item, NSUInteger index) {
    NSArray *names = [NSArray arrayWithObjects:@"pikabu", @"search", @"profile", @"settings", nil];
    if (index >= names.count) return;
    NSString *name = [names objectAtIndex:index];
    UIImage *normal = [UIImage imageNamed:[NSString stringWithFormat:@"Icon-nav-%@-normal.png", name]];
    UIImage *selected = PKTintTabIcon([UIImage imageNamed:[NSString stringWithFormat:@"Icon-nav-%@-selected.png", name]], PKAccentColor());
    if ([item respondsToSelector:@selector(setFinishedSelectedImage:withFinishedUnselectedImage:)]) {
        [item setFinishedSelectedImage:selected withFinishedUnselectedImage:normal];
    } else {
        item.image = normal;
        if ([item respondsToSelector:@selector(setSelectedImage:)]) [item setSelectedImage:selected];
    }
    NSDictionary *normalAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
        PKMutedColor(), UITextAttributeTextColor, PKFont(PKFontWeightRegular, 10), UITextAttributeFont,
        [UIColor clearColor], UITextAttributeTextShadowColor, nil];
    NSDictionary *selectedAttributes = [NSDictionary dictionaryWithObjectsAndKeys:
        PKAccentColor(), UITextAttributeTextColor, PKFont(PKFontWeightMedium, 10), UITextAttributeFont,
        [UIColor clearColor], UITextAttributeTextShadowColor, nil];
    [item setTitleTextAttributes:normalAttributes forState:UIControlStateNormal];
    [item setTitleTextAttributes:selectedAttributes forState:UIControlStateSelected];
}

static NSUInteger PKMainOrientationMask(void) {
    NSUInteger mask = (1 << UIInterfaceOrientationPortrait) | (1 << UIInterfaceOrientationLandscapeLeft) | (1 << UIInterfaceOrientationLandscapeRight);
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) mask |= (1 << UIInterfaceOrientationPortraitUpsideDown);
    return mask;
}

@interface PKNavigationController : UINavigationController
@end

@implementation PKNavigationController
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad || orientation != UIInterfaceOrientationPortraitUpsideDown;
}
- (BOOL)shouldAutorotate { return YES; }
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 90000
- (UIInterfaceOrientationMask)supportedInterfaceOrientations
#else
- (NSUInteger)supportedInterfaceOrientations
#endif
{ return PKMainOrientationMask(); }
- (void)pushViewController:(UIViewController *)controller animated:(BOOL)animated {
    if (self.viewControllers.count && !controller.navigationItem.leftBarButtonItem &&
        ![UINavigationBar instancesRespondToSelector:@selector(setBarTintColor:)]) {
        controller.navigationItem.leftBarButtonItem = PKIconBarItem(PKIconBack, PKText(@"Назад"), self, @selector(pkBack));
    }
    [super pushViewController:controller animated:animated];
}
- (void)pkBack { [self popViewControllerAnimated:YES]; }
@end

@interface PKMainViewController () <UITabBarControllerDelegate>
@end

@implementation PKMainViewController
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation {
    return [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad || orientation != UIInterfaceOrientationPortraitUpsideDown;
}
- (BOOL)shouldAutorotate { return YES; }
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 90000
- (UIInterfaceOrientationMask)supportedInterfaceOrientations
#else
- (NSUInteger)supportedInterfaceOrientations
#endif
{ return PKMainOrientationMask(); }
- (void)viewDidLoad {
    [super viewDidLoad]; self.view.backgroundColor = PKBackgroundColor();
    FeedViewController *feed = [[[FeedViewController alloc] init] autorelease];
    SearchViewController *search = [[[SearchViewController alloc] init] autorelease];
    ProfileViewController *profile = [[[ProfileViewController alloc] initWithStyle:UITableViewStylePlain] autorelease];
    SettingsViewController *settings = [[[SettingsViewController alloc] initWithStyle:UITableViewStylePlain] autorelease];
    NSArray *controllers = [NSArray arrayWithObjects:feed, search, profile, settings, nil];
    NSArray *titles = [NSArray arrayWithObjects:PKText(@"Лента"), PKText(@"Поиск"), PKText(@"Профиль"), PKText(@"Настройки"), nil];
    NSMutableArray *navigation = [NSMutableArray array];
    for (NSUInteger index = 0; index < controllers.count; index++) {
        PKNavigationController *nav = [[[PKNavigationController alloc] initWithRootViewController:[controllers objectAtIndex:index]] autorelease];
        nav.tabBarItem = [[[UITabBarItem alloc] initWithTitle:[titles objectAtIndex:index] image:nil tag:index] autorelease];
        PKApplyTabIcons(nav.tabBarItem, index);
        PKStyleNavigationBar(nav.navigationBar);
        [navigation addObject:nav];
    }
    self.viewControllers = navigation;
    self.delegate = self;
    PKStyleTabBar(self.tabBar);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:PKThemeDidChangeNotification object:nil];
}
- (void)setSelectedIndex:(NSUInteger)selectedIndex {
    NSUInteger previous = self.selectedIndex;
    [super setSelectedIndex:selectedIndex];
    if (selectedIndex != previous && self.isViewLoaded && self.view.window)
        PKAnimateTab(self.selectedViewController.view);
}
- (void)tabBarController:(UITabBarController *)controller didSelectViewController:(UIViewController *)viewController {
    (void)controller;
    PKAnimateTab(viewController.view);
}
/* the appearance proxy only reaches bars that do not exist yet */
- (void)themeChanged:(NSNotification *)notification {
    (void)notification;
    PKAnimateThemeChange(self.selectedViewController.view);
    PKAnimateThemeChange(self.tabBar);
    self.view.backgroundColor = PKBackgroundColor();
    self.view.window.backgroundColor = PKBackgroundColor();
    PKApplyGlobalTheme();
    {
        NSArray *titles = [NSArray arrayWithObjects:PKText(@"Лента"), PKText(@"Поиск"),
                                                    PKText(@"Профиль"), PKText(@"Настройки"), nil];
        NSUInteger index = 0;
        for (UINavigationController *nav in self.viewControllers) {
            if (index < titles.count) { nav.tabBarItem.title = [titles objectAtIndex:index]; PKApplyTabIcons(nav.tabBarItem, index); }
            index++;
        }
    }
    for (UINavigationController *nav in self.viewControllers) {
        PKStyleNavigationBar(nav.navigationBar);
        /* screens below the visible one are not redrawn until they come back */
        nav.view.backgroundColor = PKBackgroundColor();
        for (UIViewController *screen in nav.viewControllers) {
            if (!screen.isViewLoaded) continue;
            screen.view.backgroundColor = PKBackgroundColor();
            if ([screen.view isKindOfClass:[UITableView class]]) [(UITableView *)screen.view reloadData];
        }
    }
    PKStyleTabBar(self.tabBar);
}
- (void)dealloc { [[NSNotificationCenter defaultCenter] removeObserver:self]; [super dealloc]; }
@end

UIViewController *PKRootViewController(void) {
    return [[[PKMainViewController alloc] init] autorelease];
}
