#import "pk_motion.h"
#import <QuartzCore/QuartzCore.h>
#include <dlfcn.h>
#include <math.h>
#include "pk_spring.h"

NSTimeInterval PKMotionDuration(NSTimeInterval duration) {
    typedef BOOL (*PKReduceMotionFunction)(void);
    static PKReduceMotionFunction reduceMotion;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ reduceMotion = (PKReduceMotionFunction)dlsym(RTLD_DEFAULT, "UIAccessibilityIsReduceMotionEnabled"); });
    return reduceMotion && reduceMotion() ? 0 : duration;
}

/* core animation interpolates linearly between keys, so a key every 4 ms keeps a 120 Hz frame from landing
   between two far apart ones */
static NSUInteger PKSpringSamples(pk_spring_kind kind) {
    return MAX((NSUInteger)2, (NSUInteger)ceil(pk_spring_duration(kind) * 240.0) + 1);
}

void PKAnimateSpring(UIView *view, CGAffineTransform from, CGFloat fromAlpha, pk_spring_kind kind, NSTimeInterval delay, NSString *key) {
    if (!view.window || ![UIView areAnimationsEnabled] || PKMotionDuration(1) == 0) return;
    CGAffineTransform to = view.transform;
    CGFloat toAlpha = view.alpha;
    NSTimeInterval span = pk_spring_duration(kind);
    NSUInteger samples = PKSpringSamples(kind);
    NSMutableArray *transforms = [NSMutableArray arrayWithCapacity:samples];
    NSMutableArray *opacities = [NSMutableArray arrayWithCapacity:samples];
    for (NSUInteger i = 0; i < samples; i++) {
        CGFloat progress = (CGFloat)pk_spring_progress(kind, (double)i / (samples - 1));
        CGAffineTransform value = CGAffineTransformMake(
            from.a + (to.a - from.a) * progress, from.b + (to.b - from.b) * progress,
            from.c + (to.c - from.c) * progress, from.d + (to.d - from.d) * progress,
            from.tx + (to.tx - from.tx) * progress, from.ty + (to.ty - from.ty) * progress);
        [transforms addObject:[NSValue valueWithCATransform3D:CATransform3DMakeAffineTransform(value)]];
        /* a layer clamps opacity past one anyway */
        [opacities addObject:[NSNumber numberWithDouble:fromAlpha + (toAlpha - fromAlpha) * MIN(1, MAX(0, progress))]];
    }
    CAKeyframeAnimation *movement = [CAKeyframeAnimation animationWithKeyPath:@"transform"];
    movement.values = transforms;
    CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    fade.values = opacities;
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.duration = span;
    movement.duration = fade.duration = span;
    group.animations = [NSArray arrayWithObjects:movement, fade, nil];
    group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    if (delay > 0) {
        group.beginTime = [view.layer convertTime:CACurrentMediaTime() fromLayer:nil] + delay;
        group.fillMode = kCAFillModeBackwards;
    }
    [view.layer addAnimation:group forKey:key];
}

@interface PKPopupDone : NSObject {
    void (^_completion)(BOOL);
}
- (id)initWithCompletion:(void (^)(BOOL))completion;
@end

@implementation PKPopupDone
- (id)initWithCompletion:(void (^)(BOOL))completion {
    if ((self = [super init])) _completion = [completion copy];
    return self;
}
- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)finished {
    (void)animation;
    if (_completion) _completion(finished);
}
- (void)dealloc { [_completion release]; [super dealloc]; }
@end

static NSString *const PKPopupKey = @"pk.popup";
#define PK_POPUP_SAMPLES 121

void PKAnimatePopup(UIView *view, CGAffineTransform transform, CGFloat alpha, BOOL entering, void (^completion)(BOOL finished)) {
    CALayer *layer = view.layer;
    CALayer *visible = [layer animationForKey:PKPopupKey] ? [layer presentationLayer] : nil;
    CGAffineTransform from = visible ? CATransform3DGetAffineTransform(visible.transform) : view.transform;
    CGFloat fromAlpha = visible ? visible.opacity : view.alpha;
    [layer removeAnimationForKey:PKPopupKey];
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    view.transform = transform;
    view.alpha = alpha;
    [CATransaction commit];
    if (!view.window || ![UIView areAnimationsEnabled] || PKMotionDuration(1) == 0) {
        if (completion) completion(YES);
        return;
    }
    NSMutableArray *transforms = [NSMutableArray arrayWithCapacity:PK_POPUP_SAMPLES];
    NSMutableArray *opacities = [NSMutableArray arrayWithCapacity:PK_POPUP_SAMPLES];
    for (NSUInteger i = 0; i < PK_POPUP_SAMPLES; i++) {
        CGFloat progress = (CGFloat)pk_popup_progress(entering ? 1 : 0, (double)i / (PK_POPUP_SAMPLES - 1));
        CGAffineTransform value = CGAffineTransformMake(
            from.a + (transform.a - from.a) * progress, from.b + (transform.b - from.b) * progress,
            from.c + (transform.c - from.c) * progress, from.d + (transform.d - from.d) * progress,
            from.tx + (transform.tx - from.tx) * progress, from.ty + (transform.ty - from.ty) * progress);
        [transforms addObject:[NSValue valueWithCATransform3D:CATransform3DMakeAffineTransform(value)]];
        [opacities addObject:[NSNumber numberWithDouble:fromAlpha + (alpha - fromAlpha) * progress]];
    }
    CAKeyframeAnimation *movement = [CAKeyframeAnimation animationWithKeyPath:@"transform"];
    movement.values = transforms;
    CAKeyframeAnimation *fade = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    fade.values = opacities;
    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.duration = pk_popup_duration(entering ? 1 : 0);
    movement.duration = fade.duration = group.duration;
    group.animations = [NSArray arrayWithObjects:movement, fade, nil];
    group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    if (completion) group.delegate = (id)[[[PKPopupDone alloc] initWithCompletion:completion] autorelease];
    [layer addAnimation:group forKey:PKPopupKey];
}

void PKPlaceView(UIView *view, CGRect frame) {
    CGPoint anchor = view.layer.anchorPoint;
    view.bounds = CGRectMake(0, 0, frame.size.width, frame.size.height);
    view.center = CGPointMake(frame.origin.x + frame.size.width * anchor.x, frame.origin.y + frame.size.height * anchor.y);
}

void PKPopView(UIView *view, CGFloat from) {
    PKAnimateSpring(view, CGAffineTransformMakeScale(from, from), 1.0f, PK_SPRING_SPATIAL, 0, @"pk.pop");
}

void PKAnimatePress(UIView *view) {
    NSTimeInterval duration = PKMotionDuration(0.2);
    if (!view.window || duration <= 0) return;
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    animation.values = [NSArray arrayWithObjects:@1.0, @0.95, @1.0, nil];
    animation.keyTimes = [NSArray arrayWithObjects:@0.0, @0.45, @1.0, nil];
    animation.duration = duration;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [view.layer addAnimation:animation forKey:@"pk.press"];
}

void PKAnimateTab(UIView *view) {
    PKAnimateSpring(view, CGAffineTransformMakeTranslation(0, 16), 0.65f, PK_SPRING_SPATIAL_FAST, 0, @"pk.tab");
}

@interface PKPressFeedback : NSObject
+ (PKPressFeedback *)shared;
- (void)press:(UIControl *)control;
- (void)releasePress:(UIControl *)control;
@end

@implementation PKPressFeedback
+ (PKPressFeedback *)shared {
    static PKPressFeedback *target;
    if (!target) target = [[PKPressFeedback alloc] init];
    return target;
}
- (void)press:(UIControl *)control {
    if (!control.window || ![UIView areAnimationsEnabled] || PKMotionDuration(1) == 0) return;
    CALayer *layer = control.layer;
    CALayer *visible = [layer animationForKey:@"pk.bounce"] ? [layer presentationLayer] : nil;
    NSNumber *scale = visible ? [visible valueForKeyPath:@"transform.scale"] : nil;
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath:@"transform.scale"];
    animation.fromValue = scale ?: [NSNumber numberWithFloat:1];
    animation.toValue = [NSNumber numberWithFloat:0.92f];
    animation.duration = 0.06;
    animation.fillMode = kCAFillModeForwards;
    animation.removedOnCompletion = NO;
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [layer addAnimation:animation forKey:@"pk.bounce"];
}
- (void)releasePress:(UIControl *)control {
    CALayer *layer = control.layer;
    if (![layer animationForKey:@"pk.bounce"]) return;
    CALayer *visible = [layer presentationLayer];
    NSNumber *scale = visible ? [visible valueForKeyPath:@"transform.scale"] : nil;
    CGFloat from = scale ? [scale floatValue] : 0.92f;
    [layer removeAnimationForKey:@"pk.bounce"];
    if (!control.window || ![UIView areAnimationsEnabled] || PKMotionDuration(1) == 0) return;
    NSUInteger samples = PKSpringSamples(PK_SPRING_SPATIAL_FAST);
    NSMutableArray *values = [NSMutableArray arrayWithCapacity:samples];
    for (NSUInteger i = 0; i < samples; i++)
        [values addObject:[NSNumber numberWithDouble:from + (1 - from) * pk_spring_progress(PK_SPRING_SPATIAL_FAST, (double)i / (samples - 1))]];
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:@"transform.scale"];
    animation.values = values;
    animation.duration = pk_spring_duration(PK_SPRING_SPATIAL_FAST);
    animation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    [layer addAnimation:animation forKey:@"pk.bounce"];
}
@end

void PKAttachPressFeedback(UIControl *control) {
    if (!control) return;
    PKPressFeedback *target = [PKPressFeedback shared];
    [control addTarget:target action:@selector(press:) forControlEvents:UIControlEventTouchDown | UIControlEventTouchDragEnter];
    [control addTarget:target action:@selector(releasePress:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel | UIControlEventTouchDragExit];
}

void PKAnimateListAppearance(UITableView *tableView) {
    NSTimeInterval duration = PKMotionDuration(0.25);
    if (!tableView.window || ![UIView areAnimationsEnabled] || duration <= 0) return;
    [tableView layoutIfNeeded];
    NSArray *paths = [tableView indexPathsForVisibleRows];
    NSUInteger count = 0;
    for (NSIndexPath *path in paths) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:path];
        if (!cell || count >= 6) break;
        PKAnimateSpring(cell.contentView, CGAffineTransformMakeTranslation(0, 22), 0, PK_SPRING_SPATIAL_FAST, count * 0.035, @"pk.list.enter");
        count++;
    }
}

void PKAnimateThemeChange(UIView *view) {
    NSTimeInterval duration = PKMotionDuration(0.2);
    if (!view.window || ![UIView areAnimationsEnabled] || duration <= 0) return;
    CATransition *transition = [CATransition animation];
    transition.type = kCATransitionFade;
    transition.duration = duration;
    transition.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];
    [view.layer addAnimation:transition forKey:@"pk.theme"];
}
