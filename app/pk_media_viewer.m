#import "pk_media_viewer.h"
#import "pk_media_action_view.h"
#import "pk_media_slider.h"
#import "pk_theme.h"
#import "pk_dialog.h"
#import "pk_motion.h"
#import "pk_lang.h"
#import "pk_image.h"
#import "pk_tls_image.h"
#import "pk_media_drag.h"
#import "pk_photo_zoom.h"
#import <AVFoundation/AVFoundation.h>
#import <AssetsLibrary/AssetsLibrary.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <errno.h>
#import <string.h>
#import <fcntl.h>
#import <limits.h>
#import <sys/stat.h>
#import <unistd.h>
#import <dlfcn.h>

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 60000
#define PKMediaCenterAlignment NSTextAlignmentCenter
#else
#define PKMediaCenterAlignment UITextAlignmentCenter
#endif

#if __IPHONE_OS_VERSION_MAX_ALLOWED < 60000
@interface NSObject (PKMediaActivityInit)
- (id)initWithActivityItems:(NSArray *)items applicationActivities:(NSArray *)activities;
@end
#endif

@interface PKMediaVideoView : UIView
@end
@implementation PKMediaVideoView
+ (Class)layerClass { return [AVPlayerLayer class]; }
@end

static int PKOpenSecureVideoFile(char *path, size_t capacity, NSError **error) {
    NSString *template = [NSTemporaryDirectory() stringByAppendingPathComponent:@"weeabu-video-XXXXXX.mp4"];
    if (![template getFileSystemRepresentation:path maxLength:capacity]) {
        if (error) *error = [NSError errorWithDomain:@"WeeabuVideo" code:-1 userInfo:nil];
        return -1;
    }
    int fd = mkstemps(path, 4);
    if (fd < 0) {
        if (error) *error = [NSError errorWithDomain:@"WeeabuVideo" code:errno userInfo:nil];
        return -1;
    }
    if (fchmod(fd, S_IRUSR | S_IWUSR) != 0) {
        int failure = errno;
        close(fd); unlink(path);
        if (error) *error = [NSError errorWithDomain:@"WeeabuVideo" code:failure userInfo:nil];
        return -1;
    }
    return fd;
}

static UIImage *PKMediaSymbol(NSString *name) {
    UIImage *source = [UIImage imageNamed:[NSString stringWithFormat:@"Icon-media-%@.png", name]];
    if (!source) return nil;
    UIGraphicsBeginImageContextWithOptions(source.size, NO, source.scale);
    CGRect bounds = CGRectMake(0, 0, source.size.width, source.size.height);
    [source drawInRect:bounds];
    [[UIColor whiteColor] setFill]; UIRectFillUsingBlendMode(bounds, kCGBlendModeSourceIn);
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return result;
}

@interface PKMediaViewer () {
    NSArray *_urls;
    NSInteger _index;
    NSString *_titleText;
    NSString *_temporaryPath;
    NSString *_savePath;
    UIView *_page;
    UIImageView *_pageTransition;
    UIScrollView *_zoom;
    UIImageView *_image;
    PKMediaVideoView *_video;
    UIView *_top, *_bottom;
    UILabel *_titleLabel, *_count, *_time;
    UIButton *_close, *_share, *_more, *_play, *_mute, *_retry;
    PKMediaActionView *_playGlyph;
    PKMediaSlider *_seek;
    UIActivityIndicatorView *_spinner;
    AVPlayer *_player;
    AVPlayerItem *_playerItem;
    NSTimer *_timer;
    UIPanGestureRecognizer *_pagePan, *_dismissPan, *_videoPan;
    UIPinchGestureRecognizer *_videoPinch;
    double _videoZoom, _videoX, _videoY;
    NSUInteger _generation;
    CGSize _layoutSize;
    BOOL _paging, _closed, _chromeHidden, _scrubbing, _resumeAfterSeek, _wantsPlay, _muted, _saving;
    BOOL _previousStatusHidden;
}
@end

@implementation PKMediaViewer
- (id)init {
    if ((self = [super init])) {
        self.wantsFullScreenLayout = YES;
        self.modalPresentationStyle = UIModalPresentationFullScreen;
        self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
        _videoZoom = 1;
    }
    return self;
}
- (id)initWithMedia:(NSArray *)media title:(NSString *)title index:(NSUInteger)index {
    if ((self = [self init])) {
        _urls = [media copy]; _titleText = [title copy];
        _index = index < _urls.count ? (NSInteger)index : 0;
    }
    return self;
}
- (id)initWithImageURLs:(NSArray *)urls title:(NSString *)title index:(NSUInteger)index {
    NSMutableArray *media = [NSMutableArray array];
    for (NSString *url in urls) {
        if ([url isKindOfClass:[NSString class]])
            [media addObject:[NSDictionary dictionaryWithObjectsAndKeys:@"image", @"type", url, @"url", nil]];
    }
    return [self initWithMedia:media title:title index:index];
}
- (id)initWithVideoURL:(NSURL *)url title:(NSString *)title {
    NSDictionary *media = [NSDictionary dictionaryWithObjectsAndKeys:@"video", @"type", url.absoluteString ?: @"", @"url", nil];
    return [self initWithMedia:[NSArray arrayWithObject:media] title:title index:0];
}
- (NSString *)currentURLString {
    if (_index < 0 || _index >= (NSInteger)_urls.count) return nil;
    id item = [_urls objectAtIndex:(NSUInteger)_index];
    if (![item isKindOfClass:[NSDictionary class]]) return nil;
    id url = [item objectForKey:@"url"];
    return [url isKindOfClass:[NSString class]] ? url : nil;
}
- (BOOL)isVideo {
    if (_index < 0 || _index >= (NSInteger)_urls.count) return NO;
    id item = [_urls objectAtIndex:(NSUInteger)_index];
    return [item isKindOfClass:[NSDictionary class]] && [[item objectForKey:@"type"] isEqualToString:@"video"];
}
- (UIButton *)button:(NSString *)symbol action:(SEL)action host:(UIView *)host {
    UIButton *button = [[UIButton alloc] init];
    if (symbol) [button setImage:PKMediaSymbol(symbol) forState:UIControlStateNormal];
    PKAttachPressFeedback(button);
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [host addSubview:button];
    return button;
}
- (void)loadView {
    self.view = [[[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds] autorelease];
    self.view.backgroundColor = [UIColor blackColor]; self.view.opaque = NO;
    _page = [[UIView alloc] initWithFrame:self.view.bounds]; [self.view addSubview:_page];
    _zoom = [[UIScrollView alloc] init]; _zoom.delegate = self;
    _zoom.minimumZoomScale = 1; _zoom.maximumZoomScale = 4; _zoom.bounces = NO;
    _zoom.showsHorizontalScrollIndicator = NO; _zoom.showsVerticalScrollIndicator = NO;
    [_page addSubview:_zoom];
    _image = [[UIImageView alloc] init]; _image.contentMode = UIViewContentModeScaleAspectFit; [_zoom addSubview:_image];
    _video = [[PKMediaVideoView alloc] init]; ((AVPlayerLayer *)_video.layer).videoGravity = AVLayerVideoGravityResizeAspect;
    _video.hidden = !self.isVideo; [_page addSubview:_video];
    _top = [[UIView alloc] init]; _bottom = [[UIView alloc] init];
    _top.backgroundColor = _bottom.backgroundColor = [UIColor colorWithWhite:0 alpha:0.62];
    _bottom.layer.cornerRadius = 12;
    [self.view addSubview:_top]; [self.view addSubview:_bottom];
    _close = [self button:@"back" action:@selector(closeNow) host:_top]; _close.accessibilityLabel = PKText(@"Назад");
    _share = [self button:@"share" action:@selector(share) host:_top]; _share.accessibilityLabel = PKText(@"Поделиться");
    _more = [self button:@"ellipsisvertical" action:@selector(showMenu) host:_top]; _more.accessibilityLabel = PKText(@"Действия");
    _titleLabel = [[UILabel alloc] init]; _titleLabel.backgroundColor = [UIColor clearColor];
    _titleLabel.textColor = [UIColor whiteColor]; _titleLabel.font = PKFont(PKFontWeightBold, 17); _titleLabel.text = _titleText;
    [_top addSubview:_titleLabel];
    _count = [[UILabel alloc] init]; _count.backgroundColor = [UIColor clearColor]; _count.textColor = [UIColor whiteColor];
    _count.font = PKFont(PKFontWeightBold, 15); _count.textAlignment = PKMediaCenterAlignment; [_top addSubview:_count];
    _play = [self button:nil action:@selector(togglePlay) host:_bottom];
    _play.backgroundColor = [UIColor colorWithWhite:1 alpha:0.12]; _play.layer.cornerRadius = 20;
    _playGlyph = [[PKMediaActionView alloc] init]; [_play addSubview:_playGlyph];
    _mute = [self button:@"speaker" action:@selector(toggleMute) host:_bottom]; _mute.accessibilityLabel = PKText(@"Выключить звук");
    _time = [[UILabel alloc] init]; _time.backgroundColor = [UIColor clearColor]; _time.textColor = [UIColor whiteColor];
    _time.font = PKFont(PKFontWeightRegular, 12); _time.textAlignment = PKMediaCenterAlignment; [_bottom addSubview:_time];
    _seek = [[PKMediaSlider alloc] init];
    [_seek setTrackColor:[UIColor whiteColor]];
    [_seek addTarget:self action:@selector(beginSeek) forControlEvents:UIControlEventTouchDown];
    [_seek addTarget:self action:@selector(seekChanged) forControlEvents:UIControlEventValueChanged];
    [_seek addTarget:self action:@selector(endSeek) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    _seek.accessibilityLabel = PKText(@"Позиция видео"); [_bottom addSubview:_seek];
    _bottom.hidden = !self.isVideo;
    _spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    _spinner.hidesWhenStopped = YES; [self.view addSubview:_spinner];
    _retry = [[UIButton alloc] init]; _retry.titleLabel.font = PKFont(PKFontWeightRegular, 15);
    _retry.titleLabel.numberOfLines = 3; _retry.titleLabel.textAlignment = PKMediaCenterAlignment;
    PKAttachPressFeedback(_retry);
    [_retry addTarget:self action:@selector(retry) forControlEvents:UIControlEventTouchUpInside];
    _retry.hidden = YES; [self.view addSubview:_retry];
    UITapGestureRecognizer *doubleTap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doubleTap:)] autorelease];
    doubleTap.numberOfTapsRequired = 2; doubleTap.delegate = self; [self.view addGestureRecognizer:doubleTap];
    UITapGestureRecognizer *tap = [[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped:)] autorelease];
    tap.delegate = self; [tap requireGestureRecognizerToFail:doubleTap]; [self.view addGestureRecognizer:tap];
    UIPanGestureRecognizer *page = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(paged:)] autorelease];
    page.delegate = self; page.maximumNumberOfTouches = 1; [self.view addGestureRecognizer:page]; _pagePan = page;
    UIPanGestureRecognizer *dismiss = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragMedia:)] autorelease];
    dismiss.delegate = self; dismiss.maximumNumberOfTouches = 1; [self.view addGestureRecognizer:dismiss]; _dismissPan = dismiss;
    [page requireGestureRecognizerToFail:dismiss];
    [_zoom.panGestureRecognizer requireGestureRecognizerToFail:dismiss];
    _videoPinch = [[[UIPinchGestureRecognizer alloc] initWithTarget:self action:@selector(videoPinched:)] autorelease];
    _videoPinch.delegate = self; [self.view addGestureRecognizer:_videoPinch];
    _videoPan = [[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(videoPanned:)] autorelease];
    _videoPan.delegate = self; _videoPan.maximumNumberOfTouches = 2; [self.view addGestureRecognizer:_videoPan];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(backgrounded:) name:UIApplicationWillResignActiveNotification object:nil];
    [self loadCurrent];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    _previousStatusHidden = [UIApplication sharedApplication].statusBarHidden;
    [[UIApplication sharedApplication] setStatusBarHidden:YES withAnimation:UIStatusBarAnimationNone];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    _wantsPlay = NO; [_player pause]; [self tick];
    [[UIApplication sharedApplication] setStatusBarHidden:_previousStatusHidden withAnimation:UIStatusBarAnimationNone];
}
- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)orientation { (void)orientation; return YES; }
- (BOOL)shouldAutorotate { return YES; }
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 90000
- (UIInterfaceOrientationMask)supportedInterfaceOrientations
#else
- (NSUInteger)supportedInterfaceOrientations
#endif
{ return (1 << UIInterfaceOrientationPortrait) | (1 << UIInterfaceOrientationPortraitUpsideDown) |
         (1 << UIInterfaceOrientationLandscapeLeft) | (1 << UIInterfaceOrientationLandscapeRight); }
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect bounds = self.view.bounds;
    CGFloat width = bounds.size.width, height = bounds.size.height;
    if (!CGSizeEqualToSize(_layoutSize, bounds.size)) {
        [self cancelPaging]; _layoutSize = bounds.size;
        [_zoom setZoomScale:1 animated:NO]; [self resetVideoZoom];
    }
    _page.bounds = bounds; _page.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    _zoom.frame = bounds;
    _video.bounds = bounds; _video.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    if (_zoom.zoomScale <= 1.001) { _image.frame = _zoom.bounds; _zoom.contentSize = bounds.size; }
    _top.frame = CGRectMake(0, 0, width, 96);
    _close.frame = CGRectMake(0, 4, 48, 48);
    _titleLabel.frame = CGRectMake(56, 6, MAX(0, width - 160), 40);
    _share.frame = CGRectMake(width - 88, 4, 44, 48);
    _more.frame = CGRectMake(width - 44, 4, 44, 48);
    _count.frame = CGRectMake(48, 56, MAX(0, width - 96), 40);
    _bottom.frame = CGRectMake(0, MAX(96, height - 76), width, 76);
    _play.frame = CGRectMake(6, 2, 40, 40); _playGlyph.frame = _play.bounds;
    _mute.frame = CGRectMake(width - 50, 0, 48, 44);
    _seek.frame = CGRectMake(54, 0, MAX(0, width - 108), 44);
    _time.frame = CGRectMake(54, 44, MAX(0, width - 108), 24);
    _spinner.center = CGPointMake(width / 2, height / 2);
    _retry.frame = CGRectMake(24, height / 2 - 44, MAX(0, width - 48), 88);
}
- (void)loadCurrent {
    NSUInteger generation = ++_generation;
    [self releasePlayer];
    [_zoom setZoomScale:1 animated:NO]; [self resetVideoZoom];
    _image.image = nil; _retry.hidden = YES;
    _video.hidden = !self.isVideo; _bottom.hidden = _chromeHidden || !self.isVideo;
    _play.enabled = _seek.enabled = _mute.enabled = _share.enabled = _more.enabled = NO;
    _count.text = _urls.count > 1 ? [NSString stringWithFormat:@"%ld / %lu", (long)_index + 1, (unsigned long)_urls.count] : @"";
    [_spinner startAnimating];
    if (self.isVideo) {
        NSString *urlString = [[self currentURLString] copy];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            NSError *error = nil; char file[PATH_MAX]; NSString *path = nil;
            int fd = PKOpenSecureVideoFile(file, sizeof(file), &error);
            if (fd >= 0) {
                BOOL complete = PKTLSVideoDownload(urlString, fd, &error);
                if (close(fd) != 0 && complete) {
                    complete = NO;
                    error = [NSError errorWithDomain:@"WeeabuVideo" code:errno userInfo:nil];
                }
                if (complete) path = [[NSString stringWithUTF8String:file] retain];
                else unlink(file);
            }
            NSError *downloadError = [error retain];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (_closed || generation != _generation) {
                    if (path) [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
                } else if (!path.length) {
                    NSLog(@"weeabu: video download failed: %@", downloadError);
                    [self failed:PKText(@"Не удалось загрузить видео. Нажмите, чтобы повторить.")];
                } else {
                    [_temporaryPath release]; _temporaryPath = [path copy];
                    [self playURL:[NSURL fileURLWithPath:path]];
                }
                [downloadError release]; [path release]; [urlString release];
            });
            [pool drain];
        });
        return;
    }
    if (_index < 0 || _index >= (NSInteger)_urls.count) { [self failed:PKText(@"Изображение недоступно")]; return; }
    NSString *requested = [[self currentURLString] copy];
    PKLoadImage(requested, ^(UIImage *image) {
        if (!_closed && generation == _generation) {
            [_spinner stopAnimating];
            if (!image) [self failed:PKText(@"Не удалось загрузить изображение. Нажмите, чтобы повторить.")];
            else { _image.image = image; if (image.images.count > 1) [_image startAnimating]; _share.enabled = _more.enabled = YES; }
        }
        [requested release];
    });
}
- (void)failed:(NSString *)message {
    [self releasePlayer]; [_spinner stopAnimating];
    [_retry setTitle:message forState:UIControlStateNormal]; _retry.hidden = NO;
    _play.enabled = _seek.enabled = _mute.enabled = _share.enabled = _more.enabled = NO;
}
- (void)retry { [self loadCurrent]; }
- (void)releasePlayer {
    [_timer invalidate]; [_timer release]; _timer = nil;
    if (_playerItem) [[NSNotificationCenter defaultCenter] removeObserver:self name:nil object:_playerItem];
    [_player pause]; ((AVPlayerLayer *)_video.layer).player = nil;
    [_player release]; _player = nil; [_playerItem release]; _playerItem = nil;
    if (_temporaryPath) [[NSFileManager defaultManager] removeItemAtPath:_temporaryPath error:NULL];
    [_temporaryPath release]; _temporaryPath = nil;
    _wantsPlay = NO; _scrubbing = NO; _muted = NO;
    [_mute setImage:PKMediaSymbol(@"speaker") forState:UIControlStateNormal];
}
- (void)playURL:(NSURL *)url {
    _playerItem = [[AVPlayerItem playerItemWithURL:url] retain];
    _player = [[AVPlayer playerWithPlayerItem:_playerItem] retain];
    ((AVPlayerLayer *)_video.layer).player = _player;
    NSError *error = nil;
    // ios 7 has AVAudioSession in AVFoundation, newer sdks move it to AVFAudio
    AVAudioSession *session = [NSClassFromString(@"AVAudioSession") sharedInstance];
    NSString **categorySymbol = (NSString **)dlsym(RTLD_DEFAULT, "AVAudioSessionCategoryPlayback");
    NSString *category = categorySymbol ? *categorySymbol : nil;
    if (!session || !category || ![session setCategory:category error:&error] || ![session setActive:YES error:&error]) {
        NSLog(@"weeabu: audio session failed: %@", error);
        [self failed:PKText(@"Не удалось включить звук видео. Нажмите, чтобы повторить.")];
        return;
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(ended:) name:AVPlayerItemDidPlayToEndTimeNotification object:_playerItem];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playbackFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:_playerItem];
    _wantsPlay = [UIApplication sharedApplication].applicationState == UIApplicationStateActive;
    _timer = [[NSTimer scheduledTimerWithTimeInterval:0.2 target:self selector:@selector(tick) userInfo:nil repeats:YES] retain];
    if (_wantsPlay) [_player play];
    [self tick];
}
static NSString *PKVideoTime(double seconds) {
    if (!isfinite(seconds) || seconds < 0) seconds = 0;
    NSInteger total = (NSInteger)MIN(seconds, 2147483647);
    return [NSString stringWithFormat:@"%ld:%02ld", (long)(total / 60), (long)(total % 60)];
}
- (void)tick {
    if (!_playerItem || _closed) return;
    if (_playerItem.status == AVPlayerItemStatusFailed) {
        NSLog(@"weeabu: video playback failed: %@", _playerItem.error);
        [self failed:PKText(@"Видео не воспроизводится. Нажмите, чтобы повторить.")]; return;
    }
    if (_playerItem.status != AVPlayerItemStatusReadyToPlay) return;
    [_spinner stopAnimating]; _play.enabled = _mute.enabled = _share.enabled = _more.enabled = YES;
    double duration = CMTimeGetSeconds(_playerItem.duration), position = CMTimeGetSeconds(_player.currentTime);
    _seek.enabled = isfinite(duration) && duration > 0;
    if (!isfinite(position) || position < 0) position = 0;
    if (!_scrubbing && _seek.enabled) _seek.value = (float)MAX(0, MIN(1, position / duration));
    _time.text = [NSString stringWithFormat:@"%@ / %@", PKVideoTime(_scrubbing ? _seek.value * duration : position), PKVideoTime(duration)];
    [_playGlyph setIcon:_wantsPlay ? PKMediaIconPause : PKMediaIconPlay animated:YES];
    _play.accessibilityLabel = _wantsPlay ? PKText(@"пауза") : PKText(@"воспроизвести");
}
- (void)playbackFailed:(NSNotification *)note { NSLog(@"weeabu: video stopped: %@", note.userInfo); [self failed:PKText(@"Видео не воспроизводится. Нажмите, чтобы повторить.")]; }
- (void)ended:(NSNotification *)note { (void)note; _wantsPlay = NO; [_player pause]; [self tick]; }
- (void)togglePlay {
    if (!_player) return;
    _wantsPlay = !_wantsPlay;
    if (_wantsPlay) {
        double end = CMTimeGetSeconds(_playerItem.duration), now = CMTimeGetSeconds(_player.currentTime);
        if (isfinite(end) && isfinite(now) && now >= end - 0.1) [_player seekToTime:kCMTimeZero];
        [_player play];
    } else [_player pause];
    [self tick];
}
- (void)jump:(int)direction {
    double duration = CMTimeGetSeconds(_playerItem.duration), now = CMTimeGetSeconds(_player.currentTime);
    if (!isfinite(duration) || duration <= 0 || !isfinite(now)) return;
    double target = MAX(0, MIN(duration, now + direction * 10.0));
    [_player seekToTime:CMTimeMakeWithSeconds(target, 600)]; [self tick];
}
- (void)toggleMute {
    if (!_playerItem) return;
    _muted = !_muted;
    NSMutableArray *parameters = [NSMutableArray array];
    for (AVAssetTrack *track in [_playerItem.asset tracksWithMediaType:AVMediaTypeAudio]) {
        AVMutableAudioMixInputParameters *input = [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:track];
        [input setVolume:_muted ? 0 : 1 atTime:kCMTimeZero]; [parameters addObject:input];
    }
    AVMutableAudioMix *mix = [AVMutableAudioMix audioMix]; mix.inputParameters = parameters; _playerItem.audioMix = mix;
    [_mute setImage:PKMediaSymbol(_muted ? @"speakerslash" : @"speaker") forState:UIControlStateNormal];
    _mute.accessibilityLabel = _muted ? PKText(@"Включить звук") : PKText(@"Выключить звук");
}
- (void)beginSeek { _scrubbing = YES; _resumeAfterSeek = _wantsPlay; [_player pause]; }
- (void)seekChanged { [self tick]; }
- (void)endSeek {
    if (!_playerItem) { _scrubbing = NO; return; }
    double duration = CMTimeGetSeconds(_playerItem.duration);
    if (!_scrubbing || !isfinite(duration) || duration <= 0) { _scrubbing = NO; return; }
    _scrubbing = NO; [_player seekToTime:CMTimeMakeWithSeconds(_seek.value * duration, 600)];
    if (_resumeAfterSeek) [_player play];
}
- (void)backgrounded:(NSNotification *)note { (void)note; _wantsPlay = NO; [_player pause]; [self tick]; }
- (BOOL)videoIsZoomed { return _videoZoom > 1.03; }
- (void)resetVideoZoom {
    _videoZoom = 1; _videoX = _videoY = 0;
    [_video.layer removeAnimationForKey:@"pk.media.motion"];
    _video.transform = CGAffineTransformIdentity;
}
- (CGSize)videoPictureSize {
    CGSize area = _video.bounds.size, picture = _playerItem.presentationSize;
    if (picture.width < 1 || picture.height < 1) return area;
    CGFloat scale = MIN(area.width / picture.width, area.height / picture.height);
    return CGSizeMake(picture.width * scale, picture.height * scale);
}
- (void)clampVideoZoomWithMinimum:(double)minimum {
    CGSize picture = [self videoPictureSize], area = _video.bounds.size;
    if (area.width < 1 || picture.width < 1 || pk_photo_zoom_clamp(picture.width, picture.height, area.width, area.height, minimum, &_videoZoom, &_videoX, &_videoY) != 1) {
        _videoZoom = 1; _videoX = _videoY = 0;
    }
}
static double PKMediaSpring(double seconds) {
    double frequency = sqrt(650.0), damping = 0.6;
    double decay = frequency * damping;
    double oscillation = frequency * sqrt(1.0 - damping * damping);
    return 1.0 - exp(-decay * seconds) * (cos(oscillation * seconds) + decay / oscillation * sin(oscillation * seconds));
}
static void PKMediaAnimateSpring(UIView *view, CGAffineTransform target) {
    CALayer *layer = view.layer;
    CALayer *visible = [layer animationForKey:@"pk.media.motion"] ? [layer presentationLayer] : nil;
    CGAffineTransform from = visible ? CATransform3DGetAffineTransform(visible.transform) : view.transform;
    [layer removeAnimationForKey:@"pk.media.motion"];
    [CATransaction begin]; [CATransaction setDisableActions:YES]; view.transform = target; [CATransaction commit];
    if (!view.window || ![UIView areAnimationsEnabled] || PKMotionDuration(1) == 0) return;
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:121];
    for (NSUInteger i = 0; i < 121; i++) {
        double progress = i == 120 ? 1 : PKMediaSpring(0.48 * i / 120) / PKMediaSpring(0.48);
        CGAffineTransform value = CGAffineTransformMake(from.a + (target.a - from.a) * progress,
            from.b + (target.b - from.b) * progress, from.c + (target.c - from.c) * progress,
            from.d + (target.d - from.d) * progress, from.tx + (target.tx - from.tx) * progress,
            from.ty + (target.ty - from.ty) * progress);
        [values addObject:[NSValue valueWithCATransform3D:CATransform3DMakeAffineTransform(value)]];
    }
    CAKeyframeAnimation *movement = [CAKeyframeAnimation animationWithKeyPath:@"transform"];
    movement.values = values; movement.duration = 0.48;
    movement.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [layer addAnimation:movement forKey:@"pk.media.motion"];
}
- (void)applyVideoZoomAnimated:(BOOL)animated {
    CGAffineTransform transform = CGAffineTransformMake((CGFloat)_videoZoom, 0, 0, (CGFloat)_videoZoom, (CGFloat)_videoX, (CGFloat)_videoY);
    if (animated) PKMediaAnimateSpring(_video, transform);
    else { [_video.layer removeAnimationForKey:@"pk.media.motion"]; _video.transform = transform; }
}
- (void)videoPinched:(UIPinchGestureRecognizer *)pinch {
    if (pinch.state == UIGestureRecognizerStateBegan) [_video.layer removeAnimationForKey:@"pk.media.motion"];
    if (pinch.state == UIGestureRecognizerStateBegan || pinch.state == UIGestureRecognizerStateChanged) {
        CGPoint point = [pinch locationInView:_video.superview];
        CGSize area = _video.bounds.size;
        double next = _videoZoom * pinch.scale, x = _videoX, y = _videoY;
        if (pk_photo_zoom_about(_videoZoom, _videoX, _videoY, point.x - area.width / 2, point.y - area.height / 2, next, &x, &y) == 1) {
            _videoZoom = next; _videoX = x; _videoY = y;
        }
        pinch.scale = 1;
        [self clampVideoZoomWithMinimum:0.75];
        [self applyVideoZoomAnimated:NO];
    } else if (pinch.state == UIGestureRecognizerStateEnded || pinch.state == UIGestureRecognizerStateCancelled || pinch.state == UIGestureRecognizerStateFailed) {
        [self clampVideoZoomWithMinimum:1];
        [self applyVideoZoomAnimated:YES];
    }
}
- (void)videoPanned:(UIPanGestureRecognizer *)pan {
    if (pan.state == UIGestureRecognizerStateBegan) [_video.layer removeAnimationForKey:@"pk.media.motion"];
    if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged) {
        CGPoint move = [pan translationInView:self.view];
        [pan setTranslation:CGPointZero inView:self.view];
        _videoX += move.x; _videoY += move.y;
        [self clampVideoZoomWithMinimum:0.75];
        [self applyVideoZoomAnimated:NO];
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled || pan.state == UIGestureRecognizerStateFailed) {
        [self clampVideoZoomWithMinimum:1];
        [self applyVideoZoomAnimated:YES];
    }
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scroll { return self.isVideo ? nil : _image; }
- (void)scrollViewDidZoom:(UIScrollView *)scroll {
    CGSize size = scroll.bounds.size;
    _image.center = CGPointMake(MAX(size.width, scroll.contentSize.width) / 2, MAX(size.height, scroll.contentSize.height) / 2);
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldReceiveTouch:(UITouch *)touch {
    if (PKViewIsInDialog(touch.view)) return NO;
    for (UIView *view = touch.view; view; view = view.superview) if (view == _top || view == _bottom || view == _retry) return NO;
    return YES;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gesture shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)other {
    if (gesture == _videoPinch || other == _videoPinch || gesture == _videoPan || other == _videoPan) return (gesture == _videoPinch || gesture == _videoPan) && (other == _videoPinch || other == _videoPan);
    if (gesture == _dismissPan || other == _dismissPan) return NO;
    return _zoom.zoomScale <= 1.001 && ([gesture isKindOfClass:[UISwipeGestureRecognizer class]] || [other isKindOfClass:[UISwipeGestureRecognizer class]] || gesture.view == self.view || other.view == self.view);
}
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gesture {
    if (_paging || _closed) return NO;
    if (gesture == _videoPinch) return self.isVideo && _video.window && _playerItem;
    if (gesture == _videoPan) return [self videoIsZoomed];
    if (gesture == _pagePan || gesture == _dismissPan) {
        CGPoint speed = [(UIPanGestureRecognizer *)gesture velocityInView:self.view];
        if (_zoom.zoomScale > 1.001 || [self videoIsZoomed]) return NO;
        pk_media_drag_direction direction = pk_media_drag_direction_for(speed.x, speed.y);
        if (gesture == _dismissPan) return direction == PK_MEDIA_DRAG_VERTICAL;
        return _urls.count > 1 && direction == PK_MEDIA_DRAG_HORIZONTAL;
    }
    return ![gesture isKindOfClass:[UISwipeGestureRecognizer class]] || (_zoom.zoomScale <= 1.001);
}
- (void)doubleTap:(UITapGestureRecognizer *)tap {
    if (self.isVideo) {
        CGFloat x = [tap locationInView:self.view].x, third = self.view.bounds.size.width / 3;
        if (_playerItem && _playerItem.status == AVPlayerItemStatusReadyToPlay && (x < third || x > 2 * third)) [self jump:x < third ? -1 : 1];
        else [self togglePlay];
        return;
    }
    if (_zoom.zoomScale > 1.001) [_zoom setZoomScale:1 animated:YES];
    else {
        CGPoint point = [tap locationInView:_image];
        CGFloat width = _zoom.bounds.size.width / 2.5, height = _zoom.bounds.size.height / 2.5;
        [_zoom zoomToRect:CGRectMake(point.x - width / 2, point.y - height / 2, width, height) animated:YES];
    }
}
- (void)toggleChrome {
    _chromeHidden = !_chromeHidden;
    BOOL hide = _chromeHidden;
    if (!hide) {
        if (_top.hidden) _top.alpha = 0;
        if (_bottom.hidden) _bottom.alpha = 0;
        _top.hidden = NO;
        _bottom.hidden = !self.isVideo;
    }
    _top.userInteractionEnabled = !hide;
    _bottom.userInteractionEnabled = !hide;
    [UIView animateWithDuration:PKMotionDuration(0.2) delay:0
                       options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                    animations:^{ _top.alpha = _bottom.alpha = hide ? 0 : 1; }
                    completion:^(BOOL finished) {
        (void)finished;
        if (_chromeHidden != hide) return;
        _top.hidden = hide;
        _bottom.hidden = hide || !self.isVideo;
    }];
}
- (void)tapped:(UITapGestureRecognizer *)tap { (void)tap; [self toggleChrome]; }
- (void)cancelPaging {
    if (_paging) self.view.alpha = 1;
    [_page.layer removeAllAnimations];
    _page.transform = CGAffineTransformIdentity;
    [_pageTransition removeFromSuperview];
    [_pageTransition release];
    _pageTransition = nil;
    _paging = NO;
    self.view.backgroundColor = [UIColor blackColor];
    _top.alpha = _bottom.alpha = 1;
}

- (void)dragMedia:(UIPanGestureRecognizer *)pan {
    if (_closed || _paging) return;
    CGFloat distance = [pan translationInView:self.view].y;
    CGFloat height = self.view.bounds.size.height;
    if (pan.state == UIGestureRecognizerStateBegan || pan.state == UIGestureRecognizerStateChanged) {
        CGFloat progress = (CGFloat)pk_media_drag_progress(distance, height);
        _page.transform = CGAffineTransformMakeTranslation(0, distance);
        self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:1 - progress * 0.7];
        _top.alpha = _bottom.alpha = 1 - progress;
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled || pan.state == UIGestureRecognizerStateFailed) {
        BOOL close = pk_media_drag_should_close(distance, height, pan.state == UIGestureRecognizerStateEnded);
        _paging = YES;
        CGFloat target = close ? (distance < 0 ? -height : height) : 0;
        [UIView animateWithDuration:PKMotionDuration(0.2) delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
            _page.transform = CGAffineTransformMakeTranslation(0, target);
            self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:close ? 0 : 1];
            _top.alpha = _bottom.alpha = close ? 0 : 1;
            if (close) self.view.alpha = 0;
        } completion:^(BOOL finished) {
            if (!finished || !_paging || _closed) return;
            _paging = NO;
            if (close) [self closeAnimated:NO];
        }];
    }
}

- (void)pageToIndex:(NSInteger)index {
    if (_closed || _paging || index < 0 || index >= (NSInteger)_urls.count || index == _index) return;
    CGFloat direction = index > _index ? 1 : -1;
    UIImageView *old = [[UIImageView alloc] initWithImage:_image.image];
    old.contentMode = UIViewContentModeScaleAspectFit;
    old.frame = self.view.bounds;
    old.transform = _page.transform;
    [self.view insertSubview:old belowSubview:_top];
    _pageTransition = old;
    _paging = YES;
    _page.transform = CGAffineTransformIdentity;
    _index = index;
    [self loadCurrent];
    CGFloat width = self.view.bounds.size.width;
    _page.transform = CGAffineTransformMakeTranslation(direction * width, 0);
    [UIView animateWithDuration:PKMotionDuration(0.25) delay:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        old.transform = CGAffineTransformMakeTranslation(-direction * width, 0);
        _page.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        (void)finished;
        [old removeFromSuperview];
        if (_pageTransition == old) {
            [_pageTransition release];
            _pageTransition = nil;
            _paging = NO;
        }
    }];
}

- (void)paged:(UIPanGestureRecognizer *)pan {
    if (_closed || _paging) return;
    CGFloat drag = [pan translationInView:self.view].x;
    BOOL available = drag < 0 ? _index + 1 < (NSInteger)_urls.count : _index > 0;
    if (pan.state == UIGestureRecognizerStateChanged) {
        _page.transform = CGAffineTransformMakeTranslation(available ? drag : drag * 0.25, 0);
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        CGFloat speed = [pan velocityInView:self.view].x;
        if (pan.state == UIGestureRecognizerStateEnded && available &&
            (fabs(drag) > self.view.bounds.size.width * 0.2 || (fabs(speed) > 500 && speed * drag > 0))) {
            [self pageToIndex:_index + (drag < 0 ? 1 : -1)];
        } else {
            _paging = YES;
            [UIView animateWithDuration:PKMotionDuration(0.2) animations:^{
                _page.transform = CGAffineTransformIdentity;
            } completion:^(BOOL finished) { (void)finished; _paging = NO; }];
        }
    }
}

- (void)previous { [self pageToIndex:_index - 1]; }
- (void)next { [self pageToIndex:_index + 1]; }
- (void)showMenu {
    if (!_more.enabled || _saving) return;
    NSString *link = [[[self currentURLString] copy] autorelease];
    NSMutableArray *items = [NSMutableArray arrayWithObject:PKText(@"Сохранить")];
    if (link.length) { [items addObject:PKText(@"Скопировать ссылку")]; [items addObject:PKText(@"Открыть в Safari")]; }
    PKShowSheet(nil, items, -1, nil, ^(NSInteger index) {
        if (index == 0) [self save];
        else if (index == 1) [UIPasteboard generalPasteboard].string = link;
        else if (index == 2) {
            NSURL *url = [NSURL URLWithString:link];
            if (url) [[UIApplication sharedApplication] openURL:url];
        }
    });
}
- (void)notice:(NSString *)message {
    PKShowNotice(nil, message);
}
- (void)save {
    if (_saving) return;
    if (self.isVideo) {
        if (!_temporaryPath.length) return;
        NSString *name = [NSString stringWithFormat:@"weeabu-save-%08x.mp4", arc4random()];
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:name];
        NSError *error = nil;
        if (![[NSFileManager defaultManager] linkItemAtPath:_temporaryPath toPath:path error:&error]) {
            NSLog(@"weeabu: cannot stage video for saving: %@", error);
            [self notice:PKText(@"Не удалось сохранить видео")]; return;
        }
        if (!UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(path)) {
            [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
            [self notice:PKText(@"Не удалось сохранить видео")]; return;
        }
        _savePath = [path copy]; _saving = YES; [self retain];
        UISaveVideoAtPathToSavedPhotosAlbum(_savePath, self, @selector(video:didFinishSavingWithError:contextInfo:), NULL);
    } else if (_image.image && _index >= 0 && _index < (NSInteger)_urls.count) {
        NSString *url = [[self currentURLString] copy];
        _saving = YES; [self retain];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            NSError *error = nil;
            NSData *data = [PKTLSImageGet(url, &error) retain];
            NSError *failure = [error retain];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (!data) {
                    [self saveFinished:failure ?: [NSError errorWithDomain:@"WeeabuImage" code:-1 userInfo:nil]];
                } else {
                    ALAssetsLibrary *library = [[ALAssetsLibrary alloc] init];
                    [library writeImageDataToSavedPhotosAlbum:data metadata:nil completionBlock:^(NSURL *assetURL, NSError *saveError) {
                        (void)assetURL;
                        [saveError retain];
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self saveFinished:saveError];
                            [saveError release];
                            [library release];
                        });
                    }];
                }
                [data release]; [failure release]; [url release];
            });
            [pool drain];
        });
    }
}
- (void)saveFinished:(NSError *)error {
    _saving = NO;
    if (_savePath) [[NSFileManager defaultManager] removeItemAtPath:_savePath error:NULL];
    [_savePath release]; _savePath = nil;
    if (error) NSLog(@"weeabu: cannot save media: %@", error);
    if (!_closed) [self notice:error ? PKText(@"Не удалось сохранить") : PKText(@"Сохранено")];
    [self release];
}
- (void)video:(NSString *)path didFinishSavingWithError:(NSError *)error contextInfo:(void *)context { (void)path; (void)context; [self saveFinished:error]; }
- (void)share {
    /* the system share sheet is not used, the custom sheet has the menu choices */
    _wantsPlay = NO; [_player pause]; [self tick];
    [self showMenu];
}
- (void)closeNow { [self closeAnimated:YES]; }
- (void)closeAnimated:(BOOL)animated {
    [self cancelPaging];
    if (_closed) return;
    _closed = YES; ++_generation;
    [self releasePlayer]; [self.view endEditing:YES];
    [self dismissModalViewControllerAnimated:animated];
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self releasePlayer];
    _zoom.delegate = nil;
    [_savePath release];
    [_urls release]; [_titleText release];
    [_page release]; [_pageTransition release]; [_zoom release]; [_image release]; [_video release];
    [_top release]; [_bottom release]; [_titleLabel release]; [_count release]; [_time release];
    [_close release]; [_share release]; [_more release]; [_play release]; [_mute release]; [_retry release];
    [_playGlyph release]; [_seek release]; [_spinner release];
    [super dealloc];
}
@end
