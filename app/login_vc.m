#import "login_vc.h"
#import "pk_lang.h"
#import "pk_auth.h"
#import "pk_theme.h"
#import "pk_motion.h"
#import <QuartzCore/QuartzCore.h>

static const CGFloat kFieldHeight = 48.0f;
static const CGFloat kFormWidth = 420.0f;

@interface PKLoginViewController () <UITextFieldDelegate> {
    UIScrollView *_scroll;
    UILabel *_title;
    UILabel *_hint;
    UITextField *_username;
    UITextField *_password;
    UIButton *_login;
    UILabel *_status;
    UIActivityIndicatorView *_spinner;
    void (^_completion)(BOOL authenticated);
    BOOL _signingIn;
    BOOL _didAnimateEntry;
}
@end

@implementation PKLoginViewController
- (id)initWithCompletion:(void (^)(BOOL authenticated))completion {
    if ((self = [super init])) _completion = [completion copy];
    return self;
}
- (UITextField *)fieldWithPlaceholder:(NSString *)placeholder secure:(BOOL)secure {
    UITextField *field = [[[UITextField alloc] initWithFrame:CGRectZero] autorelease];
    field.placeholder = placeholder;
    field.secureTextEntry = secure;
    field.delegate = self;
    field.font = PKFont(PKFontWeightRegular, 16.0f);
    field.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
    field.returnKeyType = secure ? UIReturnKeyDone : UIReturnKeyNext;
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.clearButtonMode = secure ? UITextFieldViewModeNever : UITextFieldViewModeWhileEditing;
    field.layer.cornerRadius = 8.0f;
    field.layer.borderWidth = 1.0f;
    UIView *padding = [[[UIView alloc] initWithFrame:CGRectMake(0, 0, 14, 1)] autorelease];
    field.leftView = padding;
    field.leftViewMode = UITextFieldViewModeAlways;
    return field;
}
- (UIButton *)button:(NSString *)title action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    [button setTitle:title forState:UIControlStateNormal];
    button.titleLabel.font = PKFont(PKFontWeightMedium, 16.0f);
    button.layer.cornerRadius = 8.0f;
    PKAttachPressFeedback(button);
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = PKText(@"Вход в Weeabu");
    _scroll = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    _scroll.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _scroll.alwaysBounceVertical = YES;
    [self.view addSubview:_scroll];
    _title = [PKLabel(26, PKTextColor(), YES) retain];
    _title.text = PKText(@"С возвращением");
    [_scroll addSubview:_title];
    _hint = [PKLabel(14, PKMutedColor(), NO) retain];
    _hint.text = PKText(@"Вход в Weeabu");
    [_scroll addSubview:_hint];
    _username = [[self fieldWithPlaceholder:PKText(@"Логин, email или телефон") secure:NO] retain];
    _password = [[self fieldWithPlaceholder:PKText(@"Пароль") secure:YES] retain];
    [_scroll addSubview:_username];
    [_scroll addSubview:_password];
    _login = [[self button:PKText(@"Войти") action:@selector(signIn)] retain];
    [_scroll addSubview:_login];
    _status = [PKLabel(13, PKDangerColor(), NO) retain];
    _status.numberOfLines = 3;
    _status.textAlignment = NSTextAlignmentCenter;
    [_scroll addSubview:_status];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
    [_scroll addSubview:_spinner];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applyTheme) name:PKThemeDidChangeNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
    [self applyTheme];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_didAnimateEntry) return;
    _didAnimateEntry = YES;
    PKAnimateTab(_scroll);
}
- (void)applyTheme {
    self.view.backgroundColor = PKBackgroundColor();
    _title.textColor = PKTextColor();
    _hint.textColor = PKMutedColor();
    _status.textColor = PKDangerColor();
    UITextField *fields[2] = { _username, _password };
    NSUInteger index;
    for (index = 0; index < 2; index++) {
        fields[index].backgroundColor = PKCardColor();
        fields[index].textColor = PKTextColor();
        fields[index].layer.borderColor = (fields[index].isFirstResponder ? PKAccentFillColor() : PKHairlineColor()).CGColor;
        fields[index].keyboardAppearance = PKDarkThemeEnabled() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    }
    _login.backgroundColor = PKAccentFillColor();
}
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat total = self.view.bounds.size.width;
    CGFloat width = MIN(kFormWidth, total - 36.0f);
    CGFloat x = (total - width) / 2.0f;
    _title.frame = CGRectMake(x, 28, width, 34);
    _hint.frame = CGRectMake(x, 64, width, 22);
    _username.frame = CGRectMake(x, 100, width, kFieldHeight);
    _password.frame = CGRectMake(x, 156, width, kFieldHeight);
    _login.frame = CGRectMake(x, 220, width, kFieldHeight);
    _status.frame = CGRectMake(x, 280, width, 54);
    _spinner.center = _login.center;
    _scroll.contentSize = CGSizeMake(total, 348);
}
- (void)keyboardChanged:(NSNotification *)notification {
    UIEdgeInsets inset = UIEdgeInsetsZero;
    if ([[notification name] isEqualToString:UIKeyboardWillShowNotification]) {
        CGRect keyboard = [[[notification userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
        CGRect local = [self.view convertRect:keyboard fromView:nil];
        CGRect overlap = CGRectIntersection(self.view.bounds, local);
        if (!CGRectIsNull(overlap)) inset.bottom = overlap.size.height;
    }
    _scroll.contentInset = inset;
    _scroll.scrollIndicatorInsets = inset;
    UITextField *active = [_password isFirstResponder] ? _password : _username;
    if ([active isFirstResponder]) [_scroll scrollRectToVisible:CGRectInset(active.frame, 0, -12) animated:YES];
}
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    if (textField == _username) [_password becomeFirstResponder]; else [self signIn];
    return YES;
}
- (void)textFieldDidBeginEditing:(UITextField *)textField {
    textField.layer.borderColor = PKAccentFillColor().CGColor;
    if (_scroll.contentInset.bottom > 0) [_scroll scrollRectToVisible:CGRectInset(textField.frame, 0, -12) animated:YES];
}
- (void)textFieldDidEndEditing:(UITextField *)textField { textField.layer.borderColor = PKHairlineColor().CGColor; }

- (void)setBusy:(BOOL)busy {
    _signingIn = busy;
    _username.enabled = !busy;
    _password.enabled = !busy;
    _login.userInteractionEnabled = !busy;
    [_login setTitle:busy ? @"" : PKText(@"Войти") forState:UIControlStateNormal];
    if (busy) [_spinner startAnimating]; else [_spinner stopAnimating];
}
- (void)signIn {
    if (_signingIn) return;
    [_username resignFirstResponder];
    [_password resignFirstResponder];
    _status.text = @"";
    [self setBusy:YES];
    PKSignIn(_username.text, _password.text, ^(BOOL authenticated, NSString *username, NSError *error) {
        (void)username;
        [self setBusy:NO];
        if (!authenticated) { _status.text = error.localizedDescription; return; }
        if (_completion) _completion(YES);
        [self.navigationController popViewControllerAnimated:YES];
    });
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _username.delegate = nil; _password.delegate = nil;
    [_scroll release]; [_title release]; [_hint release]; [_username release]; [_password release];
    [_login release]; [_status release]; [_spinner release];
    [_completion release];
    [super dealloc];
}
@end
