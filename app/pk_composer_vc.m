#import "pk_composer_vc.h"
#import "pk_lang.h"
#import "pk_auth.h"
#import "pk_v1.h"
#import "pk_dialog.h"
#import "pk_theme.h"
#import "pk_emoji_label.h"

/* the api refuses a longer comment, so stop the text before the request */
static const NSUInteger kComposerMaxChars = 16000;

@interface PKComposerViewController () {
    PKPost *_post;
    PKComment *_parent;
    void (^_completion)(void);
    UILabel *_context;
    UITextView *_text;
    UIActivityIndicatorView *_spinner;
    BOOL _sending;
    CGFloat _keyboardHeight;
}
@end

@implementation PKComposerViewController

- (id)initWithStory:(PKPost *)post parent:(PKComment *)parent completion:(void (^)(void))completion {
    if ((self = [super init])) {
        _post = [post retain];
        _parent = [parent retain];
        _completion = [completion copy];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = _parent ? PKText(@"Ответ") : PKText(@"Комментарий");
    self.view.backgroundColor = PKCardColor();
    self.navigationItem.leftBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:PKText(@"Отмена") style:UIBarButtonItemStyleBordered target:self action:@selector(cancel)] autorelease];
    [self showSendButton];
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:PKSpinnerStyle()];
    if (_parent) {
        _context = [PKLabel(13, PKMutedColor(), NO) retain];
        _context.numberOfLines = 3;
        NSString *quote = _parent.body.length > 160 ? [[_parent.body substringToIndex:160] stringByAppendingString:@"…"] : _parent.body;
        _context.text = [NSString stringWithFormat:@"%@: %@", _parent.author, quote ?: @""];
        [self.view addSubview:_context];
    }
    _text = [[UITextView alloc] initWithFrame:CGRectZero];
    _text.delegate = self;
    _text.font = PKFont(PKFontWeightRegular, 16.0f);
    _text.textColor = PKTextColor();
    _text.backgroundColor = PKCardColor();
    _text.keyboardAppearance = PKDarkThemeEnabled() ? UIKeyboardAppearanceAlert : UIKeyboardAppearanceDefault;
    [self.view addSubview:_text];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillShowNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(keyboardChanged:) name:UIKeyboardWillHideNotification object:nil];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_text becomeFirstResponder];
}

- (void)showSendButton {
    self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithTitle:PKText(@"Отправить") style:UIBarButtonItemStyleDone target:self action:@selector(send)] autorelease];
}

- (void)setSending:(BOOL)sending {
    _sending = sending;
    _text.editable = !sending;
    if (sending) {
        [_spinner startAnimating];
        self.navigationItem.rightBarButtonItem = [[[UIBarButtonItem alloc] initWithCustomView:_spinner] autorelease];
    } else {
        [_spinner stopAnimating];
        [self showSendButton];
    }
}

- (void)keyboardChanged:(NSNotification *)note {
    CGRect end = [[[note userInfo] objectForKey:UIKeyboardFrameEndUserInfoKey] CGRectValue];
    CGRect local = [self.view convertRect:[self.view.window convertRect:end fromWindow:nil] fromView:nil];
    _keyboardHeight = [[note name] isEqualToString:UIKeyboardWillHideNotification] ? 0.0f : MAX(0.0f, self.view.bounds.size.height - local.origin.y);
    [self.view setNeedsLayout];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    CGFloat side = PKContentSideInset(bounds.size.width);
    CGFloat width = PKContentWidth(bounds.size.width);
    CGFloat y = 8.0f;
    if (_context) {
        CGFloat height = MIN(54.0f, ceilf([_context sizeThatFits:CGSizeMake(width - 32.0f, 1000.0f)].height));
        _context.frame = CGRectMake(side + 16.0f, y, width - 32.0f, height);
        y += height + 6.0f;
    }
    _text.frame = CGRectMake(side + 8.0f, y, width - 16.0f, MAX(60.0f, bounds.size.height - y - _keyboardHeight));
}

- (void)cancel {
    [_text resignFirstResponder];
    [self dismissModalViewControllerAnimated:YES];
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)replacement {
    return textView.text.length - range.length + replacement.length <= kComposerMaxChars;
}

static NSNumber *PKComposerID(NSString *value) {
    long long number = [value longLongValue];
    return number > 0 ? [NSNumber numberWithLongLong:number] : nil;
}

- (void)send {
    NSString *text = [_text.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (_sending || !text.length) return;
    NSNumber *storyID = PKComposerID(_post.storyID);
    NSNumber *parentID = _parent ? PKComposerID(_parent.commentID) : nil;
    if (!storyID || (_parent && !parentID)) {
        PKShowNotice(PKText(@"Не удалось отправить комментарий"), PKText(@"У публикации нет номера, откройте её заново."));
        return;
    }
    [self setSending:YES];
    [self submit:text storyID:storyID parentID:parentID];
}

/* the account number is kept at sign in, an older session asks the home page once */
- (void)submit:(NSString *)text storyID:(NSNumber *)storyID parentID:(NSNumber *)parentID {
    NSNumber *userID = PKSessionUserID();
    if (!userID) {
        PKCheckSession(^(BOOL authenticated, NSString *name, NSError *error) {
            (void)name;
            NSNumber *refreshed = authenticated ? PKSessionUserID() : nil;
            if (!refreshed) {
                [self setSending:NO];
                PKShowNotice(PKText(@"Не удалось отправить комментарий"), error.localizedDescription ?: PKText(@"Войдите в аккаунт и повторите."));
                return;
            }
            [self post:text storyID:storyID parentID:parentID userID:refreshed];
        });
        return;
    }
    [self post:text storyID:storyID parentID:parentID userID:userID];
}

- (void)post:(NSString *)text storyID:(NSNumber *)storyID parentID:(NSNumber *)parentID userID:(NSNumber *)userID {
    PKV1CreateComment(storyID, userID, parentID, text, YES, nil, ^(id response, NSError *error) {
        (void)response;
        if (error && PKV1IsUnauthorized(error)) {
            /* the api session is separate from the site cookies, the password opens it and is not kept */
            PKShowPasswordPrompt(PKText(@"Подтвердите вход"), PKText(@"Комментарию нужен отдельный вход в API. Пароль нигде не сохраняется."), PKText(@"Войти"), ^(NSString *password) {
                if (!password.length) { [self setSending:NO]; return; }
                PKV1Reauthenticate(password, ^(NSError *reauthError) {
                    if (reauthError) {
                        [self setSending:NO];
                        PKShowNotice(PKText(@"Не удалось войти"), reauthError.localizedDescription);
                        return;
                    }
                    [self post:text storyID:storyID parentID:parentID userID:userID];
                });
            });
            return;
        }
        if (error) {
            [self setSending:NO];
            PKShowNotice(PKText(@"Не удалось отправить комментарий"), error.localizedDescription ?: PKText(@"Неверный ответ сервера"));
            return;
        }
        void (^done)(void) = [[_completion retain] autorelease];
        [_text resignFirstResponder];
        [self dismissModalViewControllerAnimated:YES];
        if (done) done();
    });
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { (void)orientation; return YES; }
- (BOOL)shouldAutorotate { return YES; }

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    _text.delegate = nil;
    [_post release]; [_parent release]; [_completion release]; [_context release]; [_text release]; [_spinner release];
    [super dealloc];
}
@end
