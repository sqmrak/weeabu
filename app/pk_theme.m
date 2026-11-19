#import "pk_theme.h"
#import "pk_emoji_label.h"
#import <objc/message.h>
#import "../core/pk_accent.h"
#import <math.h>

NSString * const PKThemeDidChangeNotification = @"PKThemeDidChangeNotification";

static NSUInteger PKThemeRevisionValue = 0;
NSUInteger PKThemeRevision(void) { return PKThemeRevisionValue; }
void PKPostThemeChange(void) {
    PKThemeRevisionValue++;
    [[NSNotificationCenter defaultCenter] postNotificationName:PKThemeDidChangeNotification object:nil];
}

static NSString * const PKDarkKey = @"pk_dark_theme";
static NSString * const PKDefaultFeedKey = @"pk_default_feed";
static NSString * const PKCollapseCommentsKey = @"pk_collapse_comments";

/* only bites on an ipad or a phone on its side */
static const CGFloat kPKReadableWidth = 640.0f;

static UIColor *PKHex(unsigned int rgb) {
    return [UIColor colorWithRed:((rgb >> 16) & 0xff) / 255.0f
                           green:((rgb >> 8) & 0xff) / 255.0f
                            blue:(rgb & 0xff) / 255.0f
                           alpha:1.0f];
}

BOOL PKDarkThemeEnabled(void) { return [[NSUserDefaults standardUserDefaults] boolForKey:PKDarkKey]; }

static UIColor *PKPick(unsigned int dark, unsigned int light) {
    return PKHex(PKDarkThemeEnabled() ? dark : light);
}

/* the site's day green #89cc52 is 2:1 on white, so day text takes the deeper #598039 of its outlined
   buttons and dark text the lighter hover green */
static NSString * const PKAccentHueKey = @"pk_accent_hue";
static NSString * const PKAccentSaturationKey = @"pk_accent_saturation";
static NSString * const PKAccentBrightnessKey = @"pk_accent_brightness";

void PKGetAccent(float *hue, float *saturation, float *brightness) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:PKAccentHueKey]) {
        *hue = [defaults floatForKey:PKAccentHueKey];
        *saturation = [defaults floatForKey:PKAccentSaturationKey];
        *brightness = [defaults floatForKey:PKAccentBrightnessKey];
    } else {
        *hue = 0; *saturation = 0; *brightness = 0;
        pk_accent_parse_hex("548d27", 6, hue, saturation, brightness);
    }
}
void PKSetAccent(float hue, float saturation, float brightness) {
    if (!isfinite(hue) || !isfinite(saturation) || !isfinite(brightness)) return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setFloat:MAX(0, MIN(360, hue)) forKey:PKAccentHueKey];
    [defaults setFloat:MAX(0, MIN(1, saturation)) forKey:PKAccentSaturationKey];
    [defaults setFloat:MAX(0, MIN(1, brightness)) forKey:PKAccentBrightnessKey];
    PKPostThemeChange();
}
void PKResetAccent(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:PKAccentHueKey];
    [defaults removeObjectForKey:PKAccentSaturationKey];
    [defaults removeObjectForKey:PKAccentBrightnessKey];
    PKPostThemeChange();
}
static UIColor *PKCustomAccent(void) {
    float hue, saturation, brightness, r, g, b;
    PKGetAccent(&hue, &saturation, &brightness);
    pk_accent_rgb(hue, saturation, brightness, &r, &g, &b);
    return [UIColor colorWithRed:r green:g blue:b alpha:1];
}
UIColor *PKAccentColor(void) {
    return [[NSUserDefaults standardUserDefaults] objectForKey:PKAccentHueKey] ? PKCustomAccent() : PKPick(0x8aca58, 0x548d27);
}
UIColor *PKAccentFillColor(void) {
    return [[NSUserDefaults standardUserDefaults] objectForKey:PKAccentHueKey] ? PKCustomAccent() : PKPick(0x638c47, 0x65ab3c);
}
UIColor *PKOrangeColor(void) { return PKHex(0xff9900); }
UIColor *PKDangerColor(void) { return PKPick(0xcc4235, 0xe5594c); }

UIColor *PKBackgroundColor(void) { return PKPick(0x1f2327, 0xf3f4f5); }
UIColor *PKCardColor(void) { return PKPick(0x282d31, 0xffffff); }

UIColor *PKBarColor(void) { return PKCardColor(); }
UIColor *PKBarContentColor(void) { return PKTextColor(); }
UIColor *PKTextColor(void) { return PKPick(0xe0e3ea, 0x1b1e24); }
UIColor *PKMutedColor(void) { return PKPick(0x8f939d, 0x70737b); }
UIColor *PKSeparatorColor(void) { return PKPick(0x3a4044, 0xe7e8ea); }
UIColor *PKHairlineColor(void) { return PKPick(0x3a4044, 0xe7e8ea); }
UIColor *PKMediaWellColor(void) { return PKPick(0x1a1e21, 0xe7e8ea); }
UIColor *PKControlColor(void) { return PKPick(0x22272b, 0xf3f4f5); }

static void PKSetDefault(NSString *key, BOOL value) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:value forKey:key];
    [defaults synchronize];
    PKPostThemeChange();
}

void PKSetDarkThemeEnabled(BOOL enabled) { PKSetDefault(PKDarkKey, enabled); }

NSInteger PKDefaultFeedIndex(void) {
    NSInteger index = [[NSUserDefaults standardUserDefaults] integerForKey:PKDefaultFeedKey];
    return index >= 0 && index < 3 ? index : 0;
}
void PKSetDefaultFeedIndex(NSInteger index) {
    if (index < 0 || index >= 3) return;
    [[NSUserDefaults standardUserDefaults] setInteger:index forKey:PKDefaultFeedKey];
}
BOOL PKCollapseCommentBranchesEnabled(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults objectForKey:PKCollapseCommentsKey] ? [defaults boolForKey:PKCollapseCommentsKey] : YES;
}
void PKSetCollapseCommentBranchesEnabled(BOOL enabled) {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:PKCollapseCommentsKey];
}

UIFont *PKFont(PKFontWeight weight, CGFloat size) {
    NSString *name = weight == PKFontWeightBold ? @"Roboto-Bold"
                   : (weight == PKFontWeightMedium ? @"Roboto-Medium" : @"Roboto-Regular");
    UIFont *font = [UIFont fontWithName:name size:size];
    if (font) return font;
    return weight == PKFontWeightRegular ? [UIFont systemFontOfSize:size] : [UIFont boldSystemFontOfSize:size];
}

CGFloat PKContentWidth(CGFloat width) {
    return width > kPKReadableWidth ? kPKReadableWidth : width;
}

CGFloat PKContentSideInset(CGFloat width) {
    return floorf((width - PKContentWidth(width)) * 0.5f);
}

CGFloat PKCardCornerRadius(CGFloat width) {
    return PKContentSideInset(width) > 0.0f ? 12.0f : 0.0f;
}

/* the table writes the full row frame on every layout pass, so the inset goes in the setter */
@implementation PKReadableCell
- (void)setFrame:(CGRect)frame {
    CGFloat side = PKContentSideInset(frame.size.width);
    if (side > 0) { frame.origin.x += side; frame.size.width -= side * 2; }
    [super setFrame:frame];
}
@end

UIActivityIndicatorViewStyle PKSpinnerStyle(void) {
    return PKDarkThemeEnabled() ? UIActivityIndicatorViewStyleWhite
                                : UIActivityIndicatorViewStyleGray;
}

static BOOL PKRespondsTo(id object, SEL selector) {
    return object && [object respondsToSelector:selector];
}

static void PKSetColor(id object, SEL selector, UIColor *color) {
    if (!PKRespondsTo(object, selector)) return;
    ((void (*)(id, SEL, id))objc_msgSend)(object, selector, color);
}

/* ios 5 and 6 read UITextAttribute keys and ios 7 the NSAttributedString ones, each ignores the other set */
static NSDictionary *PKBarTitleAttributes(void) {
    UIColor *ink = PKBarContentColor();
    UIFont *font = PKFont(PKFontWeightMedium, 17.0f);
    NSMutableDictionary *attributes = [NSMutableDictionary dictionary];
    [attributes setObject:ink forKey:@"NSColor"];
    [attributes setObject:font forKey:@"NSFont"];
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [attributes setObject:ink forKey:UITextAttributeTextColor];
    [attributes setObject:font forKey:UITextAttributeFont];
    [attributes setObject:[UIColor clearColor] forKey:UITextAttributeTextShadowColor];
#pragma clang diagnostic pop
    return attributes;
}

/* dark glyphs on the day card, light ones on the dark card and the green ios 5 and 6 bar */
static void PKStyleStatusBar(void) {
    UIStatusBarStyle style = PKDarkThemeEnabled() ? UIStatusBarStyleBlackOpaque : UIStatusBarStyleDefault;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    [[UIApplication sharedApplication] setStatusBarStyle:style];
#pragma clang diagnostic pop
}

static UIImage *PKSolidBarImage(UIColor *color) {
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 1), NO, 0);
    [color setFill];
    UIRectFill(CGRectMake(0, 0, 1, 1));
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

static NSDictionary *PKBarButtonAttributes(void) {
    /* ios 5 and 6 fill a bar button with the bar tint (the accent), so accent text on it is unreadable and
       takes the plain ink. flat buttons since ios 7 keep the accent */
    BOOL filled = ![UINavigationBar instancesRespondToSelector:@selector(setBarTintColor:)];
    return [NSDictionary dictionaryWithObjectsAndKeys:filled ? PKTextColor() : PKAccentColor(), UITextAttributeTextColor,
            PKFont(PKFontWeightMedium, 16), UITextAttributeFont,
            [UIColor clearColor], UITextAttributeTextShadowColor, nil];
}

static void PKStyleNavigationItem(UINavigationItem *item) {
    NSMutableArray *buttons = [NSMutableArray array];
    if (item.leftBarButtonItem) [buttons addObject:item.leftBarButtonItem];
    if (item.rightBarButtonItem) [buttons addObject:item.rightBarButtonItem];
    if (item.backBarButtonItem) [buttons addObject:item.backBarButtonItem];
    for (UIBarButtonItem *button in buttons)
        [button setTitleTextAttributes:PKBarButtonAttributes() forState:UIControlStateNormal];
}

void PKStyleNavigationBar(UINavigationBar *bar) {
    if (!bar) return;
    PKStyleStatusBar();
    bar.translucent = NO;
    bar.barStyle = PKDarkThemeEnabled() ? UIBarStyleBlack : UIBarStyleDefault;
    bar.tintColor = PKAccentColor();
    if ([bar respondsToSelector:@selector(setBackgroundImage:forBarMetrics:)])
        [bar setBackgroundImage:PKSolidBarImage(PKBarColor()) forBarMetrics:UIBarMetricsDefault];
    if ([bar respondsToSelector:@selector(setBarTintColor:)])
        PKSetColor(bar, @selector(setBarTintColor:), PKBarColor());
    if ([bar respondsToSelector:@selector(setTitleTextAttributes:)])
        [bar setTitleTextAttributes:PKBarTitleAttributes()];
    for (UINavigationItem *item in bar.items) {
        PKStyleNavigationItem(item);
        /* ios 5 and 6 ignore new titleTextAttributes until the title is set again, which left light ink on
           a white bar */
        NSString *title = [[item.title copy] autorelease];
        if (title && !item.titleView) {
            item.title = nil;
            item.title = title;
        }
    }
}

void PKStyleTabBar(UITabBar *bar) {
    if (!bar) return;
    if ([bar respondsToSelector:@selector(setBackgroundImage:)])
        [bar setBackgroundImage:PKSolidBarImage(PKBarColor())];
    if ([bar respondsToSelector:@selector(setSelectionIndicatorImage:)])
        [bar setSelectionIndicatorImage:PKSolidBarImage([UIColor clearColor])];
    if ([bar respondsToSelector:@selector(setBarTintColor:)])
        PKSetColor(bar, @selector(setBarTintColor:), PKBarColor());
    if ([bar respondsToSelector:@selector(setSelectedImageTintColor:)])
        PKSetColor(bar, @selector(setSelectedImageTintColor:), PKAccentColor());
    if ([bar respondsToSelector:@selector(setTintColor:)])
        PKSetColor(bar, @selector(setTintColor:), PKAccentColor());
    if ([bar respondsToSelector:@selector(setUnselectedItemTintColor:)])
        PKSetColor(bar, @selector(setUnselectedItemTintColor:), PKMutedColor());
    if ([bar respondsToSelector:@selector(setTranslucent:)])
        ((void (*)(id, SEL, BOOL))objc_msgSend)(bar, @selector(setTranslucent:), NO);
}

void PKStyleSearchBar(UISearchBar *bar) {
    if (!bar) return;
    if ([bar respondsToSelector:@selector(setBackgroundImage:)])
        [bar setBackgroundImage:PKSolidBarImage(PKBackgroundColor())];
    if ([bar respondsToSelector:@selector(setBarTintColor:)])
        PKSetColor(bar, @selector(setBarTintColor:), PKBackgroundColor());
    bar.tintColor = PKAccentColor();
}

/* the appearance proxy records only appearance selectors and raises on the rest, so real bars are styled
   through PKStyleNavigationBar and PKStyleTabBar */
void PKApplyGlobalTheme(void) {
    [[UISwitch appearance] setOnTintColor:PKAccentFillColor()];
    [[UIBarButtonItem appearance] setTitleTextAttributes:PKBarButtonAttributes() forState:UIControlStateNormal];
    id navigationBar = [UINavigationBar appearance];
    if ([UINavigationBar instancesRespondToSelector:@selector(setBarTintColor:)])
        ((void (*)(id, SEL, id))objc_msgSend)(navigationBar, @selector(setBarTintColor:),
                                              PKBarColor());
    if ([UINavigationBar instancesRespondToSelector:@selector(setTitleTextAttributes:)])
        ((void (*)(id, SEL, id))objc_msgSend)(navigationBar,
                                              @selector(setTitleTextAttributes:),
                                              PKBarTitleAttributes());
    if ([UITabBar instancesRespondToSelector:@selector(setBarTintColor:)])
        ((void (*)(id, SEL, id))objc_msgSend)([UITabBar appearance],
                                              @selector(setBarTintColor:), PKBarColor());
    PKStyleStatusBar();
}

UIColor *PKSectionTitleColor(void) {
    return PKDarkThemeEnabled() ? [UIColor whiteColor] : [UIColor blackColor];
}

UIView *PKSectionHeader(NSString *title, CGFloat width, CGFloat height) {
    UIView *view = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)] autorelease];
    view.backgroundColor = PKBackgroundColor();
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    CGFloat side = PKContentSideInset(width);
    UILabel *label = [[[UILabel alloc] initWithFrame:CGRectMake(side + 16, 0, MAX(0, width - side * 2 - 32), height)] autorelease];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.backgroundColor = [UIColor clearColor];
    label.font = PKFont(PKFontWeightMedium, 12.0f);
    label.textColor = PKSectionTitleColor();
    label.text = title;
    [view addSubview:label];
    return view;
}

void PKStyleTable(UITableView *tableView) {
    tableView.backgroundColor = PKBackgroundColor();
    tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
    tableView.separatorColor = PKSeparatorColor();
    if (PKRespondsTo(tableView, @selector(setSectionIndexBackgroundColor:)))
        PKSetColor(tableView, @selector(setSectionIndexBackgroundColor:), [UIColor clearColor]);
}

UILabel *PKLabel(CGFloat size, UIColor *color, BOOL bold) {
    UILabel *label = [[[PKEmojiLabel alloc] initWithFrame:CGRectZero] autorelease];
    label.backgroundColor = [UIColor clearColor];
    label.textColor = color;
    label.font = PKFont(bold ? PKFontWeightMedium : PKFontWeightRegular, size);
    return label;
}
