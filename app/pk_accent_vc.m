#import "pk_accent_vc.h"
#import "pk_accent_editor.h"
#import "pk_theme.h"
#import "pk_lang.h"
#import "pk_motion.h"
#import <QuartzCore/QuartzCore.h>

@interface PKAccentViewController () {
    UIScrollView *_scroll;
    PKAccentEditor *_editor;
    UIButton *_reset;
}
@end

@implementation PKAccentViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = PKText(@"Цвет акцента");
    self.view.backgroundColor = PKBackgroundColor();
    _scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_scroll];
    _editor = [[PKAccentEditor alloc] initWithFrame:CGRectZero];
    float hue, saturation, brightness;
    PKGetAccent(&hue, &saturation, &brightness);
    _editor.hue = hue; _editor.saturation = saturation; _editor.brightness = brightness;
    [_editor addTarget:self action:@selector(commitAccent) forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:_editor];
    _reset = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
    [_reset setTitle:PKText(@"Зелёный по умолчанию") forState:UIControlStateNormal];
    [_reset setTitleColor:PKAccentColor() forState:UIControlStateNormal];
    _reset.titleLabel.font = PKFont(PKFontWeightMedium, 16);
    _reset.layer.cornerRadius = 12;
    _reset.backgroundColor = PKCardColor();
    PKAttachPressFeedback(_reset);
    [_reset addTarget:self action:@selector(resetAccent) forControlEvents:UIControlEventTouchUpInside];
    [_scroll addSubview:_reset];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:PKThemeDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardShown:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardHidden:) name:UIKeyboardWillHideNotification object:nil];
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat width = MIN(480, _scroll.bounds.size.width);
    CGFloat x = floor((_scroll.bounds.size.width - width) / 2);
    _editor.frame = CGRectMake(x, 0, width, _editor.preferredHeight);
    _reset.frame = CGRectMake(x + 16, _editor.preferredHeight + 8, width - 32, 48);
    _scroll.contentSize = CGSizeMake(_scroll.bounds.size.width, _editor.preferredHeight + 72);
}
- (void)commitAccent { PKSetAccent(_editor.hue, _editor.saturation, _editor.brightness); }
- (void)resetAccent {
    PKResetAccent();
    float hue, saturation, brightness;
    PKGetAccent(&hue, &saturation, &brightness);
    _editor.hue = hue; _editor.saturation = saturation; _editor.brightness = brightness;
}
- (void)themeChanged:(NSNotification *)note {
    (void)note;
    self.view.backgroundColor = PKBackgroundColor();
    _reset.backgroundColor = PKCardColor();
    [_reset setTitleColor:PKAccentColor() forState:UIControlStateNormal];
    PKStyleNavigationBar(self.navigationController.navigationBar);
}
- (void)keyboardShown:(NSNotification *)note {
    CGRect frame = [[[note userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect keyboard = [self.view convertRect:frame fromView:nil];
    CGFloat overlap = MAX(0, CGRectGetMaxY(self.view.bounds) - CGRectGetMinY(keyboard));
    _scroll.contentInset = UIEdgeInsetsMake(0, 0, overlap, 0);
    _scroll.scrollIndicatorInsets = _scroll.contentInset;
    [_scroll scrollRectToVisible:[_editor convertRect:_editor.editingRect toView:_scroll] animated:YES];
}
- (void)keyboardHidden:(NSNotification *)note {
    (void)note;
    _scroll.contentInset = UIEdgeInsetsZero;
    _scroll.scrollIndicatorInsets = UIEdgeInsetsZero;
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_scroll release]; [_editor release]; [_reset release];
    [super dealloc];
}
@end
