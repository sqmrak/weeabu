#import "pk_dialog.h"
#import "pk_theme.h"
#import "pk_lang.h"
#import "pk_motion.h"
#import <QuartzCore/QuartzCore.h>

/* a window has no rotation of its own before ios 8, so the root view turns it */
static UIView *PKDialogHost(void) {
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    if (!window && [[[UIApplication sharedApplication] windows] count]) window = [[[UIApplication sharedApplication] windows] objectAtIndex:0];
    UIViewController *controller = window.rootViewController;
    while (controller.presentedViewController) controller = controller.presentedViewController;
    return controller.view ?: window;
}

typedef enum { PKDialogKindAlert, PKDialogKindSheet, PKDialogKindPassword } PKDialogKind;

@interface PKDialogView : UIView <UITextFieldDelegate> {
    PKDialogKind _kind;
    UIButton *_backdrop;
    UIView *_card;
    UITextField *_field;
    NSString *_title;
    NSString *_message;
    NSArray *_buttons;
    NSString *_cancel;
    NSInteger _destructive;
    BOOL _cancelable;
    BOOL _finished;
    PKDialogHandler _handler;
    void (^_passwordHandler)(NSString *);
    CGFloat _keyboard;
}
- (id)initWithKind:(PKDialogKind)kind title:(NSString *)title message:(NSString *)message buttons:(NSArray *)buttons cancel:(NSString *)cancel
       destructive:(NSInteger)destructive cancelable:(BOOL)cancelable handler:(PKDialogHandler)handler passwordHandler:(void (^)(NSString *))passwordHandler;
- (void)present;
@end

@implementation PKDialogView

static const CGFloat PKDialogRowHeight = 52.0f;

- (id)initWithKind:(PKDialogKind)kind title:(NSString *)title message:(NSString *)message buttons:(NSArray *)buttons cancel:(NSString *)cancel
       destructive:(NSInteger)destructive cancelable:(BOOL)cancelable handler:(PKDialogHandler)handler passwordHandler:(void (^)(NSString *))passwordHandler {
    if ((self = [super initWithFrame:CGRectZero])) {
        _kind = kind;
        _title = [title copy];
        _message = [message copy];
        _buttons = [buttons copy];
        _cancel = [cancel copy];
        _destructive = destructive;
        _cancelable = cancelable;
        _handler = [handler copy];
        _passwordHandler = [passwordHandler copy];
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.accessibilityViewIsModal = YES;
        _backdrop = [[UIButton buttonWithType:UIButtonTypeCustom] retain];
        _backdrop.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5f];
        _backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [_backdrop addTarget:self action:@selector(backdropTapped) forControlEvents:UIControlEventTouchUpInside];
        [self addSubview:_backdrop];
        _card = [[UIView alloc] initWithFrame:CGRectZero];
        _card.backgroundColor = PKCardColor();
        _card.layer.cornerRadius = kind == PKDialogKindSheet ? 20.0f : 22.0f;
        [self addSubview:_card];
        [self buildContent];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillChangeFrameNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
    }
    return self;
}

- (UIButton *)rowWithTitle:(NSString *)title tag:(NSInteger)tag color:(UIColor *)color weight:(PKFontWeight)weight {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.tag = tag;
    button.backgroundColor = PKControlColor();
    button.layer.cornerRadius = 14.0f;
    button.titleLabel.font = PKFont(weight, 16);
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:color forState:UIControlStateNormal];
    PKAttachPressFeedback(button);
    [button addTarget:self action:@selector(rowTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)buildContent {
    if (_title.length) {
        UILabel *label = PKLabel(_kind == PKDialogKindSheet ? 14 : 18, _kind == PKDialogKindSheet ? PKMutedColor() : PKTextColor(), _kind != PKDialogKindSheet);
        label.tag = 901;
        label.text = _title;
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 0;
        [_card addSubview:label];
    }
    if (_message.length) {
        UILabel *label = PKLabel(14, PKMutedColor(), NO);
        label.tag = 902;
        label.text = _message;
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 0;
        [_card addSubview:label];
    }
    if (_kind == PKDialogKindPassword) {
        _field = [[UITextField alloc] initWithFrame:CGRectZero];
        _field.secureTextEntry = YES;
        _field.backgroundColor = PKControlColor();
        _field.textColor = PKTextColor();
        _field.font = PKFont(PKFontWeightRegular, 16);
        _field.layer.cornerRadius = 12.0f;
        _field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
        _field.autocorrectionType = UITextAutocorrectionTypeNo;
        _field.autocapitalizationType = UITextAutocapitalizationTypeNone;
        _field.returnKeyType = UIReturnKeyDone;
        _field.keyboardAppearance = PKDarkThemeEnabled() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
        _field.placeholder = PKText(@"Пароль");
        _field.leftView = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 10)] autorelease];
        _field.leftViewMode = UITextFieldViewModeAlways;
        _field.delegate = self;
        [_card addSubview:_field];
    }
    NSUInteger count = _buttons.count;
    for (NSUInteger i = 0; i < count; i++) {
        BOOL danger = (NSInteger)i == _destructive;
        BOOL primary = _kind != PKDialogKindSheet && i == count - 1 && !danger;
        UIColor *color = danger ? PKDangerColor() : (primary ? PKAccentColor() : PKTextColor());
        [_card addSubview:[self rowWithTitle:[_buttons objectAtIndex:i] tag:(NSInteger)i color:color weight:primary || danger ? PKFontWeightMedium : PKFontWeightRegular]];
    }
    if (_kind == PKDialogKindSheet && _cancel.length)
        [_card addSubview:[self rowWithTitle:_cancel tag:-1 color:PKAccentColor() weight:PKFontWeightMedium]];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat width = self.bounds.size.width, height = self.bounds.size.height;
    _backdrop.frame = self.bounds;
    CGFloat cardWidth = _kind == PKDialogKindSheet ? MIN(width - 16.0f, 480.0f) : MIN(width - 48.0f, 340.0f);
    CGFloat inner = cardWidth - 32.0f;
    CGFloat y = 18.0f;
    UILabel *title = (UILabel *)[_card viewWithTag:901];
    UILabel *message = (UILabel *)[_card viewWithTag:902];
    if (title) {
        CGFloat h = [title sizeThatFits:CGSizeMake(inner, 1000)].height;
        title.frame = CGRectMake(16, y, inner, h);
        y += h + (message || _field ? 8.0f : 12.0f);
    }
    if (message) {
        CGFloat h = [message sizeThatFits:CGSizeMake(inner, 1000)].height;
        message.frame = CGRectMake(16, y, inner, h);
        y += h + 14.0f;
    }
    if (_field) { _field.frame = CGRectMake(16, y, inner, 44); y += 44 + 12.0f; }
    BOOL sheet = _kind == PKDialogKindSheet;
    for (UIView *view in _card.subviews) {
        if (![view isKindOfClass:[UIButton class]]) continue;
        if (view.tag < 0) continue;
        view.frame = CGRectMake(16, y, inner, PKDialogRowHeight - 8.0f);
        y += PKDialogRowHeight;
    }
    UIView *cancel = [_card viewWithTag:-1];
    if (sheet && cancel) {
        y += 4.0f;
        cancel.frame = CGRectMake(16, y, inner, PKDialogRowHeight - 8.0f);
        y += PKDialogRowHeight;
    }
    y += sheet ? 6.0f : 10.0f;
    CGFloat cardHeight = y;
    CGFloat x = floorf((width - cardWidth) / 2);
    CGFloat bottom = MAX(8.0f, _keyboard + 8.0f);
    CGFloat top = sheet ? height - cardHeight - bottom : floorf((height - _keyboard - cardHeight) / 2);
    PKPlaceView(_card, CGRectMake(x, MAX(20.0f, top), cardWidth, cardHeight));
}

- (void)keyboardChanged:(NSNotification *)note {
    CGRect frame = [[[note userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect local = [self convertRect:[self.window convertRect:frame fromWindow:nil] fromView:nil];
    _keyboard = [note.name isEqualToString:UIKeyboardWillHideNotification] ? 0 : MAX(0.0f, self.bounds.size.height - local.origin.y);
    [UIView animateWithDuration:0.25 animations:^{ [self layoutSubviews]; }];
}

/* below the screen for a sheet, a small step down in size for an alert */
- (CGAffineTransform)hiddenTransform {
    if (_kind == PKDialogKindSheet) return CGAffineTransformMakeTranslation(0, _card.bounds.size.height + 40.0f);
    return CGAffineTransformMakeScale(0.9f, 0.9f);
}

- (void)present {
    UIView *host = PKDialogHost();
    self.frame = host.bounds;
    [host addSubview:self];
    [self layoutIfNeeded];
    BOOL sheet = _kind == PKDialogKindSheet;
    _backdrop.alpha = 0;
    _card.alpha = sheet ? 1.0f : 0.0f;
    _card.transform = [self hiddenTransform];
    PKAnimatePopup(_backdrop, CGAffineTransformIdentity, 1, YES, nil);
    PKAnimatePopup(_card, CGAffineTransformIdentity, 1, YES, nil);
    if (_field) [_field becomeFirstResponder];
}

- (void)finishWithIndex:(NSInteger)index password:(NSString *)password {
    if (_finished) return;
    _finished = YES;
    [_field resignFirstResponder];
    self.userInteractionEnabled = NO;
    PKDialogHandler handler = [[_handler retain] autorelease];
    void (^passwordHandler)(NSString *) = [[_passwordHandler retain] autorelease];
    NSString *typed = [[password copy] autorelease];
    BOOL sheet = _kind == PKDialogKindSheet;
    void (^done)(void) = ^{
        [self removeFromSuperview];
        if (handler) handler(index);
        if (passwordHandler) passwordHandler(typed);
        [self release];
    };
    [self retain];
    /* same curve and retargeting as ios/exteria: it leaves from where it shows now */
    PKAnimatePopup(_backdrop, CGAffineTransformIdentity, 0, NO, nil);
    PKAnimatePopup(_card, [self hiddenTransform], sheet ? 1.0f : 0.0f, NO, ^(BOOL finished) { (void)finished; done(); });
}

- (void)backdropTapped {
    if (_kind == PKDialogKindSheet || _cancelable) [self finishWithIndex:-1 password:nil];
}
- (void)rowTapped:(UIButton *)button {
    /* the press spring overshoots while the card is already leaving */
    [button.layer removeAllAnimations];
    if (_kind == PKDialogKindPassword) {
        [self finishWithIndex:button.tag password:button.tag == (NSInteger)_buttons.count - 1 ? _field.text : nil];
        return;
    }
    [self finishWithIndex:button.tag password:nil];
}
- (BOOL)textFieldShouldReturn:(UITextField *)field {
    [self finishWithIndex:(NSInteger)_buttons.count - 1 password:field.text];
    return YES;
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _field.delegate = nil;
    [_backdrop release]; [_card release]; [_field release]; [_title release]; [_message release]; [_buttons release]; [_cancel release];
    [_handler release]; [_passwordHandler release];
    [super dealloc];
}
@end

BOOL PKViewIsInDialog(UIView *view) {
    for (; view; view = view.superview) if ([view isKindOfClass:[PKDialogView class]]) return YES;
    return NO;
}

static void PKPresentDialog(PKDialogView *dialog) {
    [dialog present];
    /* the host view owns it while it is up, finishWithIndex balances this */
}

void PKShowAlert(NSString *title, NSString *message, NSArray *buttons, NSInteger destructive, BOOL cancelable, PKDialogHandler handler) {
    if (![buttons count]) buttons = [NSArray arrayWithObject:@"OK"];
    PKDialogView *dialog = [[PKDialogView alloc] initWithKind:PKDialogKindAlert title:title message:message buttons:buttons cancel:nil
                                                    destructive:destructive cancelable:cancelable handler:handler passwordHandler:nil];
    PKPresentDialog(dialog);
    [dialog release];
}

void PKShowNotice(NSString *title, NSString *message) {
    PKShowAlert(title, message, [NSArray arrayWithObject:@"OK"], -1, YES, nil);
}

void PKShowSheet(NSString *title, NSArray *items, NSInteger destructive, NSString *cancel, PKDialogHandler handler) {
    if (![items count]) return;
    PKDialogView *dialog = [[PKDialogView alloc] initWithKind:PKDialogKindSheet title:title message:nil buttons:items cancel:cancel ?: PKText(@"Отмена")
                                                    destructive:destructive cancelable:YES handler:handler passwordHandler:nil];
    PKPresentDialog(dialog);
    [dialog release];
}

void PKShowPasswordPrompt(NSString *title, NSString *message, NSString *confirm, void (^handler)(NSString *password)) {
    NSArray *buttons = [NSArray arrayWithObjects:PKText(@"Отмена"), confirm.length ? confirm : @"OK", nil];
    PKDialogView *dialog = [[PKDialogView alloc] initWithKind:PKDialogKindPassword title:title message:message buttons:buttons cancel:nil
                                                    destructive:-1 cancelable:YES handler:nil passwordHandler:handler];
    PKPresentDialog(dialog);
    [dialog release];
}
