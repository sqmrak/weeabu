#import "pk_media_action_view.h"

#import <QuartzCore/QuartzCore.h>

#include <math.h>

#import "pk_motion.h"

#define BASE_SIDE 48.0
#define LINE_WIDTH 3.0
#define RING_INSET 4.0
#define RING_PERIOD 2.5
#define RING_START_DEGREES 112.0
#define MIN_ARC_DEGREES 4.0

#define DOWNLOAD_TO_CANCEL_STAGE1 0.5
#define DOWNLOAD_TO_CANCEL_STAGE2 0.2
#define DOWNLOAD_TO_CANCEL_STAGE3 0.3

static NSString *const PKRingTurnKey = @"media.ring.turn";

static CGFloat PKEase(CGFloat t) {
    t = t < 0 ? 0 : (t > 1 ? 1 : t);
    return t * t * (3 - 2 * t);
}

@interface PKMediaActionView () {
    UIColor *_discColor;
    UIColor *_inkColor;
    PKMediaIcon _current;
    PKMediaIcon _next;
    CGFloat _transition;
    BOOL _animating;
    CFTimeInterval _duration;
    CFTimeInterval _lastTick;
    CADisplayLink *_link;
    CAShapeLayer *_ring;
    float _progress;
    CGSize _ringSize;
}
@end

@implementation PKMediaActionView

@synthesize discColor = _discColor;
@synthesize inkColor = _inkColor;

- (id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    self.userInteractionEnabled = NO;
    _inkColor = [[UIColor whiteColor] retain];
    _current = _next = PKMediaIconPlay;
    _transition = 1;
    _ring = [[CAShapeLayer alloc] init];
    _ring.fillColor = NULL;
    _ring.lineCap = kCALineCapRound;
    _ring.opacity = 0;
    _ring.strokeEnd = MIN_ARC_DEGREES / 360.0;
    [self.layer addSublayer:_ring];
    return self;
}

- (void)dealloc {
    [_link invalidate];
    [_discColor release];
    [_inkColor release];
    [_ring release];
    [super dealloc];
}

- (PKMediaIcon)icon {
    return _next;
}

- (CGFloat)unit {
    return MIN(self.bounds.size.width, self.bounds.size.height) / BASE_SIDE;
}

- (CGFloat)discAlpha {
    if (!_animating) return _next == PKMediaIconNone ? 0 : 1;
    if (_next == PKMediaIconNone) return 1 - _transition;
    if (_current == PKMediaIconNone) return _transition;
    return 1;
}

- (void)applyDisc {
    CGFloat alpha = [self discAlpha];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.layer.backgroundColor = _discColor ? [_discColor colorWithAlphaComponent:CGColorGetAlpha(_discColor.CGColor) * alpha].CGColor : NULL;
    [CATransaction commit];
}

- (void)setDiscColor:(UIColor *)color {
    if (color == _discColor) return;
    [_discColor release];
    _discColor = [color retain];
    [self applyDisc];
}

- (void)setInkColor:(UIColor *)color {
    if (color == _inkColor) return;
    [_inkColor release];
    _inkColor = [color retain];
    _ring.strokeColor = _inkColor.CGColor;
    [self setNeedsDisplay];
}


- (void)layoutSubviews {
    [super layoutSubviews];
    CGSize size = self.bounds.size;
    if (CGSizeEqualToSize(size, _ringSize)) return;
    _ringSize = size;
    CGFloat unit = [self unit];
    self.layer.cornerRadius = MIN(size.width, size.height) / 2;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _ring.bounds = self.bounds;
    _ring.position = CGPointMake(size.width / 2, size.height / 2);
    _ring.lineWidth = LINE_WIDTH * unit;
    _ring.strokeColor = _inkColor.CGColor;
    _ring.path = [UIBezierPath bezierPathWithArcCenter:CGPointMake(size.width / 2, size.height / 2) radius:MIN(size.width, size.height) / 2 - RING_INSET * unit
                                            startAngle:0 endAngle:(CGFloat)(M_PI * 2) clockwise:YES].CGPath;
    [CATransaction commit];
    [self syncRing];
}


- (CGFloat)ringAlpha {
    BOOL from = _current == PKMediaIconCancel, to = _next == PKMediaIconCancel;
    if (!_animating || (from && to)) return to ? 1 : 0;
    if (to) return _current == PKMediaIconDownload ? MAX(0, (_transition - DOWNLOAD_TO_CANCEL_STAGE1) / (1 - DOWNLOAD_TO_CANCEL_STAGE1)) : _transition;
    if (from) return _next == PKMediaIconDownload ? MAX(0, 1 - _transition / (DOWNLOAD_TO_CANCEL_STAGE2 + DOWNLOAD_TO_CANCEL_STAGE3)) : MAX(0, 1 - _transition * 2);
    return 0;
}

- (void)syncRing {
    CGFloat alpha = [self ringAlpha];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _ring.opacity = (float)alpha;
    [CATransaction commit];
    BOOL turning = (_next == PKMediaIconCancel || _current == PKMediaIconCancel) && self.window != nil && !(PKMotionDuration(1) == 0) && alpha > 0;
    if (!turning) {
        [_ring removeAnimationForKey:PKRingTurnKey];
        return;
    }
    if ([_ring animationForKey:PKRingTurnKey]) return;
    CABasicAnimation *turn = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    turn.fromValue = [NSNumber numberWithDouble:RING_START_DEGREES * M_PI / 180];
    turn.toValue = [NSNumber numberWithDouble:RING_START_DEGREES * M_PI / 180 + M_PI * 2];
    turn.duration = RING_PERIOD;
    turn.repeatCount = HUGE_VALF;
    turn.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [_ring addAnimation:turn forKey:PKRingTurnKey];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) {
        [self endTransition];
        [self applyDisc];
        [self setNeedsDisplay];
    }
    [self syncRing];
}

- (void)setProgress:(float)progress {
    progress = progress < 0 ? 0 : (progress > 1 ? 1 : progress);
    if (progress == _progress) return;
    BOOL grows = progress > _progress;
    _progress = progress;
    CGFloat end = MAX(MIN_ARC_DEGREES / 360.0, progress);
    [CATransaction begin];
    if (grows && self.window && !(PKMotionDuration(1) == 0)) {
        [CATransaction setAnimationDuration:0.2];
        [CATransaction setAnimationTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut]];
    } else {
        [CATransaction setDisableActions:YES];
    }
    _ring.strokeEnd = end;
    [CATransaction commit];
}


static CFTimeInterval PKTransitionSeconds(PKMediaIcon from, PKMediaIcon to) {
    if ((from == PKMediaIconPlay && to == PKMediaIconPause) || (from == PKMediaIconPause && to == PKMediaIconPlay)) return 0.3;
    if (from == PKMediaIconDownload && to == PKMediaIconCancel) return 0.4;
    return 0.22;
}

- (void)setIcon:(PKMediaIcon)icon animated:(BOOL)animated {
    if (icon == _next) return;
    if (animated && self.window && !(PKMotionDuration(1) == 0)) {
                if (_animating) _current = _next;
        _next = icon;
        _transition = 0;
        _animating = YES;
        _duration = PKTransitionSeconds(_current, _next);
        if (icon == PKMediaIconCancel && _current != PKMediaIconCancel) {
                        [_ring removeAnimationForKey:PKRingTurnKey];
            _progress = 0;
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            _ring.strokeEnd = MIN_ARC_DEGREES / 360.0;
            [CATransaction commit];
        }
        _lastTick = CACurrentMediaTime();
        if (!_link) {
            _link = [[CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)] retain];
            [_link addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        }
    } else {
        [self endTransition];
        _current = _next = icon;
        _transition = 1;
        if (icon == PKMediaIconCancel) {
            _progress = 0;
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            _ring.strokeEnd = MIN_ARC_DEGREES / 360.0;
            [CATransaction commit];
        }
    }
    [self syncRing];
    [self applyDisc];
    [self setNeedsDisplay];
}

- (void)endTransition {
    [_link invalidate];
    [_link release];
    _link = nil;
    if (_animating) _current = _next;
    _animating = NO;
    _transition = 1;
}

- (void)tick:(CADisplayLink *)link {
    (void)link;
    CFTimeInterval now = CACurrentMediaTime();
    CFTimeInterval dt = MIN(now - _lastTick, 1.0 / 30);
    _lastTick = now;
    _transition += (CGFloat)(dt / _duration);
    if (_transition >= 1) {
        [self endTransition];
        _current = _next;
    }
    [self syncRing];
    [self applyDisc];
    [self setNeedsDisplay];
}


static void PKLine(CGContextRef context, CGFloat x1, CGFloat y1, CGFloat x2, CGFloat y2) {
    CGContextMoveToPoint(context, x1, y1);
    CGContextAddLineToPoint(context, x2, y2);
    CGContextStrokePath(context);
}

static void PKArc(CGContextRef context, CGFloat cx, CGFloat cy, CGFloat radius, CGFloat startDegrees, CGFloat sweepDegrees) {
    CGContextAddArc(context, cx, cy, radius, startDegrees * (CGFloat)M_PI / 180, (startDegrees + sweepDegrees) * (CGFloat)M_PI / 180, 0);
    CGContextStrokePath(context);
}

- (void)setInk:(CGContextRef)context alpha:(CGFloat)alpha {
    CGFloat unit = [self unit];
    CGContextSetStrokeColorWithColor(context, [_inkColor colorWithAlphaComponent:alpha * CGColorGetAlpha(_inkColor.CGColor)].CGColor);
    CGContextSetFillColorWithColor(context, [_inkColor colorWithAlphaComponent:alpha * CGColorGetAlpha(_inkColor.CGColor)].CGColor);
    CGContextSetLineWidth(context, LINE_WIDTH * unit);
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineJoin(context, kCGLineJoinRound);
}

static void PKDrawCross(CGContextRef context, CGFloat cx, CGFloat cy, CGFloat half) {
    PKLine(context, cx - half, cy - half, cx + half, cy + half);
    PKLine(context, cx + half, cy - half, cx - half, cy + half);
}

- (void)drawArrowAndCross:(CGContextRef)context folding:(CGFloat)t {
    CGFloat unit = [self unit];
    CGFloat cx = self.bounds.size.width / 2, cy = self.bounds.size.height / 2;
    CGFloat yStart = cy - 9 * unit, yEnd = cy + 9 * unit;
    CGFloat yStart2 = cy + 1 * unit, yEnd2 = cy + 12 * unit;
    CGFloat y1, y2, x1, x2, y3;
    if (t <= DOWNLOAD_TO_CANCEL_STAGE1) {
        CGFloat forward = t / DOWNLOAD_TO_CANCEL_STAGE1, back = 1 - forward;
        y1 = yStart + (yStart2 - yStart) * forward;
        y2 = yEnd + (yEnd2 - yEnd) * forward;
        x1 = cx - 8 * back * unit;
        x2 = cx + 8 * back * unit;
        y3 = y2 - 8 * back * unit;
    } else {
        CGFloat progress = t - DOWNLOAD_TO_CANCEL_STAGE1;
        CGFloat third = progress / (DOWNLOAD_TO_CANCEL_STAGE2 + DOWNLOAD_TO_CANCEL_STAGE3);
        CGFloat first, second;
        if (progress > DOWNLOAD_TO_CANCEL_STAGE2) {
            progress -= DOWNLOAD_TO_CANCEL_STAGE2;
            first = 1;
            second = progress / DOWNLOAD_TO_CANCEL_STAGE3;
        } else {
            first = progress / DOWNLOAD_TO_CANCEL_STAGE2;
            second = 0;
        }
        CGFloat d = 13 * unit * unit;
        CGFloat start = 100 * second;
        PKArc(context, cx - d / 2, yEnd2, d / 2, start, 104 * third - start);
        y1 = yStart2 + (yEnd2 - yStart2) * first;
        y2 = y3 = yEnd2;
        x1 = x2 = cx;
        if (second > 0) {
            CGContextSaveGState(context);
            CGContextTranslateCTM(context, cx, cy);
            CGContextRotateCTM(context, -45 * (1 - second) * (CGFloat)M_PI / 180);
            CGContextTranslateCTM(context, -cx, -cy);
            [self setInk:context alpha:second];
            PKDrawCross(context, cx, cy, 7 * second * unit);
            CGContextRestoreGState(context);
            [self setInk:context alpha:1];
        }
    }
    if (y1 != y2) PKLine(context, cx, y1, cx, y2);
    if (x1 != cx) {
        PKLine(context, x1, y3, cx, y2);
        PKLine(context, x2, y3, cx, y2);
    }
}

- (void)drawPlay:(CGContextRef)context toPause:(CGFloat)p scale:(CGFloat)scale alpha:(CGFloat)alpha {
    if (scale <= 0 || alpha <= 0) return;
    static const CGPoint triangle[4] = {{-6, -9}, {9, 0}, {9, 0}, {-6, 0}};
    static const CGPoint bar[4] = {{-9, -7}, {9, -7}, {9, -2.5}, {-9, -2.5}};
    CGFloat unit = [self unit];
    CGFloat shaped = PKEase(p);
    CGFloat cx = self.bounds.size.width / 2, cy = self.bounds.size.height / 2;
    [self setInk:context alpha:alpha];
    CGContextSetLineWidth(context, 1.4 * unit);
    for (int half = 0; half < 2; ++half) {
        CGContextSaveGState(context);
        CGContextTranslateCTM(context, cx + 1 * (1 - shaped) * unit, cy);
        CGContextRotateCTM(context, 90 * shaped * (CGFloat)M_PI / 180);
        CGContextScaleCTM(context, scale * unit, (half ? -1 : 1) * scale * unit);
        for (int i = 0; i < 4; ++i) {
            CGFloat x = triangle[i].x + (bar[i].x - triangle[i].x) * shaped;
            CGFloat y = triangle[i].y + (bar[i].y - triangle[i].y) * shaped;
            if (i == 0) CGContextMoveToPoint(context, x, y);
            else CGContextAddLineToPoint(context, x, y);
        }
        CGContextClosePath(context);
        CGContextDrawPath(context, kCGPathFillStroke);
        CGContextRestoreGState(context);
    }
    [self setInk:context alpha:1];
}

- (void)drawGlyph:(PKMediaIcon)icon context:(CGContextRef)context scale:(CGFloat)scale rotation:(CGFloat)rotation alpha:(CGFloat)alpha {
    if (scale <= 0 || alpha <= 0) return;
    CGFloat unit = [self unit];
    CGFloat cx = self.bounds.size.width / 2, cy = self.bounds.size.height / 2;
    switch (icon) {
    case PKMediaIconPlay: [self drawPlay:context toPause:0 scale:scale alpha:alpha]; return;
    case PKMediaIconPause: [self drawPlay:context toPause:1 scale:scale alpha:alpha]; return;
    case PKMediaIconNone: return;
    case PKMediaIconFile: {
                CGContextSaveGState(context);
        CGContextTranslateCTM(context, cx, cy);
        CGContextRotateCTM(context, rotation * (CGFloat)M_PI / 180);
        CGContextScaleCTM(context, scale * unit, scale * unit);
        [self setInk:context alpha:alpha];
        CGContextSetLineWidth(context, 1.2);
        CGContextMoveToPoint(context, -8, -11);
        CGContextAddLineToPoint(context, 2, -11);
        CGContextAddLineToPoint(context, 8, -5);
        CGContextAddLineToPoint(context, 8, 11);
        CGContextAddLineToPoint(context, -8, 11);
        CGContextClosePath(context);
        CGContextDrawPath(context, kCGPathFillStroke);
        CGColorRef back = _discColor ? _discColor.CGColor : [UIColor colorWithWhite:0 alpha:0.45f].CGColor;
        CGContextSetFillColorWithColor(context, back);
        CGContextMoveToPoint(context, 2, -11);
        CGContextAddLineToPoint(context, 2, -5);
        CGContextAddLineToPoint(context, 8, -5);
        CGContextClosePath(context);
        CGContextDrawPath(context, kCGPathFillStroke);
        CGContextRestoreGState(context);
        [self setInk:context alpha:1];
        return;
    }
    default: break;
    }
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, cx, cy);
    CGContextRotateCTM(context, rotation * (CGFloat)M_PI / 180);
    CGContextScaleCTM(context, scale, scale);
    CGContextTranslateCTM(context, -cx, -cy);
    [self setInk:context alpha:alpha];
    if (icon == PKMediaIconCancel) {
        PKDrawCross(context, cx, cy, 7 * unit);
    } else {
        PKLine(context, cx, cy - 9 * unit, cx, cy + 9 * unit);
        PKLine(context, cx - 8 * unit, cy + 1 * unit, cx, cy + 9 * unit);
        PKLine(context, cx + 8 * unit, cy + 1 * unit, cx, cy + 9 * unit);
    }
    CGContextRestoreGState(context);
    [self setInk:context alpha:1];
}

- (void)drawRect:(CGRect)rect {
    (void)rect;
    CGContextRef context = UIGraphicsGetCurrentContext();
    [self setInk:context alpha:1];
    if (!_animating || _current == _next) {
        [self drawGlyph:_next context:context scale:1 rotation:0 alpha:1];
        return;
    }
    PKMediaIcon from = _current, to = _next;
    CGFloat t = _transition;
    if ((from == PKMediaIconDownload && to == PKMediaIconCancel) || (from == PKMediaIconCancel && to == PKMediaIconDownload)) {
        [self drawArrowAndCross:context folding:from == PKMediaIconDownload ? t : 1 - t];
        return;
    }
    if ((from == PKMediaIconPlay && to == PKMediaIconPause) || (from == PKMediaIconPause && to == PKMediaIconPlay)) {
        [self drawPlay:context toPause:to == PKMediaIconPause ? t : 1 - t scale:1 alpha:1];
        return;
    }
        CGFloat grow, shrink;
    if (from == PKMediaIconNone || from == PKMediaIconCancel) {
        grow = t;
        shrink = 1 - t;
    } else {
        grow = MIN(1, t / 0.5);
        shrink = MAX(0, 1 - t / 0.5);
    }
    [self drawGlyph:from context:context scale:shrink rotation:0 alpha:shrink];
    [self drawGlyph:to context:context scale:grow rotation:to == PKMediaIconCancel ? 45 * (1 - t) : 0 alpha:grow];
}

@end
