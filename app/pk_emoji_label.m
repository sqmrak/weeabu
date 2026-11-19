#import "pk_emoji_label.h"
#import "exteria_emoji_store.h"
#import <CoreText/CoreText.h>
#include <stdint.h>

static NSString *const PKEmojiAttribute = @"PKEmoji";
static const NSUInteger PKEmojiTextLimit = 32768;

static CGFloat PKEmojiSize(void *info) { return (CGFloat)(uintptr_t)info / 100.0f; }
static CGFloat PKEmojiAscent(void *info) { return PKEmojiSize(info) * 0.82f; }
static CGFloat PKEmojiDescent(void *info) { return PKEmojiSize(info) * 0.23f; }
static CGFloat PKEmojiWidth(void *info) { return PKEmojiSize(info); }
static void PKEmojiDelegateRelease(void *info) { (void)info; }

static NSMutableAttributedString *PKEmojiString(NSString *text, UIFont *font, UIColor *color) {
    if (!text.length || text.length > PKEmojiTextLimit) return nil;
    NSUInteger length = text.length;
    uint16_t *characters = malloc(length * sizeof(*characters));
    exteria_emoji_span *spans = malloc(length * sizeof(*spans));
    if (!characters || !spans) { free(characters); free(spans); return nil; }
    [text getCharacters:characters range:NSMakeRange(0, length)];
    size_t count = exteria_emoji_scan(characters, length, spans, length);
    free(characters);
    if (!count) { free(spans); return nil; }
    CTFontRef face = CTFontCreateWithName((CFStringRef)font.fontName, font.pointSize, NULL);
    if (!face) { free(spans); return nil; }
    NSMutableAttributedString *string = [[[NSMutableAttributedString alloc] initWithString:text] autorelease];
    [string addAttribute:(id)kCTFontAttributeName value:(id)face range:NSMakeRange(0, length)];
    [string addAttribute:(id)kCTForegroundColorAttributeName value:(id)color.CGColor range:NSMakeRange(0, length)];
    CFRelease(face);
    CTRunDelegateCallbacks callbacks;
    memset(&callbacks, 0, sizeof(callbacks));
    callbacks.version = kCTRunDelegateCurrentVersion;
    callbacks.getAscent = PKEmojiAscent;
    callbacks.getDescent = PKEmojiDescent;
    callbacks.getWidth = PKEmojiWidth;
    callbacks.dealloc = PKEmojiDelegateRelease;
    for (size_t i = count; i > 0; i--) {
        exteria_emoji_span span = spans[i - 1];
        if (!ExteriaEmojiHasPicture(span.entry)) continue;
        CTRunDelegateRef delegate = CTRunDelegateCreate(&callbacks, (void *)(uintptr_t)(font.pointSize * 125));
        if (!delegate) continue;
        NSRange range = NSMakeRange(span.start, span.length);
        [string replaceCharactersInRange:range withString:@"\uFFFC"];
        NSRange place = NSMakeRange(span.start, 1);
        [string addAttribute:(id)kCTRunDelegateAttributeName value:(id)delegate range:place];
        CFRelease(delegate);
        [string addAttribute:(id)kCTForegroundColorAttributeName value:(id)[UIColor clearColor].CGColor range:place];
        [string addAttribute:PKEmojiAttribute value:[NSNumber numberWithUnsignedInteger:span.entry] range:place];
    }
    free(spans);
    return string;
}

static CGFloat PKEmojiLayout(NSString *text, UIFont *font, UIColor *color, CGFloat width, CGFloat maxHeight,
                             NSInteger maxLines, NSTextAlignment alignment, BOOL draw) {
    NSMutableAttributedString *string = PKEmojiString(text, font, color);
    if (!string || width < 1 || maxHeight < 1) return -1;
    CTTypesetterRef typesetter = CTTypesetterCreateWithAttributedString((CFAttributedStringRef)string);
    if (!typesetter) return -1;
    CGFloat baseline = 0, previousDescent = 0;
    CFIndex start = 0, length = (CFIndex)string.length;
    NSInteger lineCount = 0;
    while (start < length && (!maxLines || lineCount < maxLines)) {
        CFIndex fit = CTTypesetterSuggestLineBreak(typesetter, start, width);
        if (fit <= 0) break;
        BOOL lastLine = maxLines > 0 && lineCount + 1 == maxLines && start + fit < length;
        CTLineRef line = NULL;
        if (lastLine) {
            CTLineRef rest = CTTypesetterCreateLine(typesetter, CFRangeMake(start, length - start));
            NSMutableDictionary *attributes = [NSMutableDictionary dictionaryWithDictionary:[string attributesAtIndex:(NSUInteger)start effectiveRange:NULL]];
            [attributes removeObjectForKey:(id)kCTRunDelegateAttributeName];
            [attributes removeObjectForKey:PKEmojiAttribute];
            [attributes setObject:(id)color.CGColor forKey:(id)kCTForegroundColorAttributeName];
            NSAttributedString *token = [[[NSAttributedString alloc] initWithString:@"…" attributes:attributes] autorelease];
            CTLineRef ellipsis = CTLineCreateWithAttributedString((CFAttributedStringRef)token);
            if (rest && ellipsis) line = CTLineCreateTruncatedLine(rest, width, kCTLineTruncationEnd, ellipsis);
            if (ellipsis) CFRelease(ellipsis);
            if (rest) CFRelease(rest);
            fit = length - start;
        }
        if (!line) line = CTTypesetterCreateLine(typesetter, CFRangeMake(start, fit));
        if (!line) break;
        CGFloat ascent = 0, descent = 0, leading = 0;
        CTLineGetTypographicBounds(line, &ascent, &descent, &leading);
        CGFloat nextBaseline = baseline + (lineCount ? previousDescent + leading : 0) + ascent;
        if (lineCount && nextBaseline + descent > maxHeight + 0.5f) { CFRelease(line); break; }
        baseline = nextBaseline;
        previousDescent = descent;
        CGFloat flush = alignment == NSTextAlignmentCenter ? 0.5f : (alignment == NSTextAlignmentRight ? 1.0f : 0.0f);
        CGFloat x = (CGFloat)CTLineGetPenOffsetForFlush(line, flush, width);
        if (draw) {
            CGContextRef context = UIGraphicsGetCurrentContext();
            CGContextSaveGState(context);
            CGContextTranslateCTM(context, x, baseline);
            CGContextScaleCTM(context, 1, -1);
            CGContextSetTextMatrix(context, CGAffineTransformIdentity);
            CGContextSetTextPosition(context, 0, 0);
            CTLineDraw(line, context);
            CGContextRestoreGState(context);
            CFArrayRef runs = CTLineGetGlyphRuns(line);
            for (CFIndex j = 0; j < CFArrayGetCount(runs); j++) {
                CTRunRef run = CFArrayGetValueAtIndex(runs, j);
                NSNumber *entry = [(NSDictionary *)CTRunGetAttributes(run) objectForKey:PKEmojiAttribute];
                if (!entry) continue;
                CGPoint position;
                CGFloat runAscent, runDescent;
                CTRunGetPositions(run, CFRangeMake(0, 1), &position);
                CGFloat runWidth = (CGFloat)CTRunGetTypographicBounds(run, CFRangeMake(0, 0), &runAscent, &runDescent, NULL);
                CGRect rect = CGRectMake(x + position.x, baseline - runAscent, runWidth, runAscent + runDescent);
                CGFloat side = rect.size.width;
                ExteriaDrawEmoji([entry unsignedIntegerValue], CGRectMake(rect.origin.x, CGRectGetMidY(rect) - side / 2, side, side));
            }
        }
        lineCount++;
        start += fit;
        CFRelease(line);
    }
    CFRelease(typesetter);
    return ceilf(baseline + previousDescent);
}

CGFloat PKEmojiTextHeight(NSString *text, UIFont *font, CGFloat width, CGFloat maxHeight) {
    CGFloat height = PKEmojiLayout(text, font, [UIColor blackColor], width, maxHeight, 0, NSTextAlignmentLeft, NO);
    if (height >= 0) return height;
    return [text sizeWithFont:font constrainedToSize:CGSizeMake(width, maxHeight) lineBreakMode:NSLineBreakByWordWrapping].height;
}

@implementation PKEmojiLabel
- (void)drawTextInRect:(CGRect)rect {
    NSUInteger misses = ExteriaEmojiMissCount();
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGFloat height = PKEmojiLayout(self.text, self.font, self.textColor, rect.size.width, rect.size.height,
                                   self.numberOfLines, self.textAlignment, NO);
    if (height >= 0) {
        CGContextSaveGState(context);
        CGContextClipToRect(context, rect);
        CGContextTranslateCTM(context, rect.origin.x, rect.origin.y + floorf(MAX(0, rect.size.height - height) / 2));
        PKEmojiLayout(self.text, self.font, self.textColor, rect.size.width, rect.size.height,
                      self.numberOfLines, self.textAlignment, YES);
        CGContextRestoreGState(context);
    } else [super drawTextInRect:rect];
    if (ExteriaEmojiMissCount() != misses) ExteriaEmojiRedrawWhenLoaded(self);
}
@end
