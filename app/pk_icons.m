#import "pk_icons.h"
#import "pk_theme.h"
#import "pk_motion.h"

static NSCache *PKIconCache(void) {
    static NSCache *cache;
    if (!cache) {
        cache = [[NSCache alloc] init];
        cache.countLimit = 48;
    }
    return cache;
}

static void PKDrawIcon(CGContextRef context, PKIconKind kind, CGFloat size, UIColor *color) {
    CGFloat unit = size / 24.0f;
    CGContextScaleCTM(context, unit, unit);
    CGContextSetStrokeColorWithColor(context, color.CGColor);
    CGContextSetFillColorWithColor(context, color.CGColor);
    CGContextSetLineWidth(context, 2.2f);
    CGContextSetLineCap(context, kCGLineCapRound);
    CGContextSetLineJoin(context, kCGLineJoinRound);
    switch (kind) {
        case PKIconArrowUp:
        case PKIconArrowDown: {
            CGFloat tip = kind == PKIconArrowUp ? 4.5f : 19.5f;
            CGFloat tail = kind == PKIconArrowUp ? 19.5f : 4.5f;
            CGFloat wing = kind == PKIconArrowUp ? 6.5f : -6.5f;
            CGContextMoveToPoint(context, 12.0f, tail);
            CGContextAddLineToPoint(context, 12.0f, tip);
            CGContextMoveToPoint(context, 5.5f, tip + wing);
            CGContextAddLineToPoint(context, 12.0f, tip);
            CGContextAddLineToPoint(context, 18.5f, tip + wing);
            CGContextStrokePath(context);
            break;
        }
        case PKIconComment: {
            CGContextMoveToPoint(context, 6.0f, 4.5f);
            CGContextAddLineToPoint(context, 18.0f, 4.5f);
            CGContextAddArcToPoint(context, 21.0f, 4.5f, 21.0f, 7.5f, 3.0f);
            CGContextAddLineToPoint(context, 21.0f, 13.0f);
            CGContextAddArcToPoint(context, 21.0f, 16.0f, 18.0f, 16.0f, 3.0f);
            CGContextAddLineToPoint(context, 11.0f, 16.0f);
            CGContextAddLineToPoint(context, 7.0f, 20.0f);
            CGContextAddLineToPoint(context, 7.0f, 16.0f);
            CGContextAddLineToPoint(context, 6.0f, 16.0f);
            CGContextAddArcToPoint(context, 3.0f, 16.0f, 3.0f, 13.0f, 3.0f);
            CGContextAddLineToPoint(context, 3.0f, 7.5f);
            CGContextAddArcToPoint(context, 3.0f, 4.5f, 6.0f, 4.5f, 3.0f);
            CGContextStrokePath(context);
            break;
        }
        case PKIconShare: {
            CGContextMoveToPoint(context, 8.5f, 10.0f);
            CGContextAddLineToPoint(context, 6.0f, 10.0f);
            CGContextAddLineToPoint(context, 6.0f, 20.0f);
            CGContextAddLineToPoint(context, 18.0f, 20.0f);
            CGContextAddLineToPoint(context, 18.0f, 10.0f);
            CGContextAddLineToPoint(context, 15.5f, 10.0f);
            CGContextMoveToPoint(context, 12.0f, 15.0f);
            CGContextAddLineToPoint(context, 12.0f, 3.5f);
            CGContextMoveToPoint(context, 8.0f, 7.0f);
            CGContextAddLineToPoint(context, 12.0f, 3.0f);
            CGContextAddLineToPoint(context, 16.0f, 7.0f);
            CGContextStrokePath(context);
            break;
        }
        case PKIconBack: {
            CGContextMoveToPoint(context, 14.5f, 5.0f);
            CGContextAddLineToPoint(context, 7.5f, 12.0f);
            CGContextAddLineToPoint(context, 14.5f, 19.0f);
            CGContextMoveToPoint(context, 8.0f, 12.0f);
            CGContextAddLineToPoint(context, 20.0f, 12.0f);
            CGContextStrokePath(context);
            break;
        }
        case PKIconRefresh: {
            CGContextAddArc(context, 12.0f, 12.0f, 7.0f, -0.8f, 4.5f, 0);
            CGContextMoveToPoint(context, 17.2f, 4.3f);
            CGContextAddLineToPoint(context, 18.0f, 8.0f);
            CGContextAddLineToPoint(context, 14.3f, 7.3f);
            CGContextStrokePath(context);
            break;
        }
        case PKIconPlay: {
            CGContextMoveToPoint(context, 8.0f, 5.0f);
            CGContextAddLineToPoint(context, 19.0f, 12.0f);
            CGContextAddLineToPoint(context, 8.0f, 19.0f);
            CGContextClosePath(context);
            CGContextFillPath(context);
            break;
        }
    }
}

UIImage *PKIcon(PKIconKind kind, CGFloat size, UIColor *color) {
    CGFloat red = 0, green = 0, blue = 0, alpha = 0;
    CGColorRef cg = color.CGColor;
    const CGFloat *parts = CGColorGetComponents(cg);
    CGColorSpaceModel model = CGColorSpaceGetModel(CGColorGetColorSpace(cg));
    if (model == kCGColorSpaceModelMonochrome && CGColorGetNumberOfComponents(cg) == 2) {
        /* ios 5 and 6 refuse getRed:green:blue:alpha: for whiteColor and other grey-space colors, which
           drew the play badge black */
        red = green = blue = parts[0];
        alpha = parts[1];
    } else if (![color getRed:&red green:&green blue:&blue alpha:&alpha]) {
        /* a pattern color has no rgb, draw it black rather than not at all */
        alpha = 1.0f;
        color = [UIColor blackColor];
    }
    NSString *key = [NSString stringWithFormat:@"%d:%.1f:%.3f:%.3f:%.3f:%.3f:%.1f", (int)kind, size, red, green, blue, alpha, [UIScreen mainScreen].scale];
    static NSUInteger filledUnder;
    if (filledUnder != PKThemeRevision()) {
        [PKIconCache() removeAllObjects];
        filledUnder = PKThemeRevision();
    }
    UIImage *cached = [PKIconCache() objectForKey:key];
    if (cached) return cached;
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(size, size), NO, 0.0f);
    PKDrawIcon(UIGraphicsGetCurrentContext(), kind, size, color);
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    if (image) [PKIconCache() setObject:image forKey:key];
    return image;
}

@interface PKBarIconButton : UIButton {
    PKIconKind _iconKind;
}
- (id)initWithKind:(PKIconKind)kind;
@end

@implementation PKBarIconButton
- (id)initWithKind:(PKIconKind)kind {
    if ((self = [super initWithFrame:CGRectMake(0, 0, 44, 44)])) {
        _iconKind = kind;
        PKAttachPressFeedback(self);
        self.adjustsImageWhenHighlighted = YES;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(themeChanged:) name:PKThemeDidChangeNotification object:nil];
        [self themeChanged:nil];
    }
    return self;
}
- (void)themeChanged:(NSNotification *)notification {
    (void)notification;
    [self setImage:PKIcon(_iconKind, 24, PKBarContentColor()) forState:UIControlStateNormal];
}
- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}
@end

UIBarButtonItem *PKIconBarItem(PKIconKind kind, NSString *label, id target, SEL action) {
    PKBarIconButton *button = [[[PKBarIconButton alloc] initWithKind:kind] autorelease];
    button.accessibilityLabel = label;
    [button addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    return [[[UIBarButtonItem alloc] initWithCustomView:button] autorelease];
}
