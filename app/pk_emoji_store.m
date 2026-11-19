#import "exteria_emoji_store.h"

#import "pk_image.h"
#import <CoreText/CoreText.h>

#define PACK_NAME @"emoji"
#define PACK_EXTENSION @"pack"
#define PACK_HEADER 12u

/* mapped, so its 7 MB cost no memory until a picture is read */
static NSData *ExteriaEmojiPack(void) {
    static NSData *pack;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSString *path = [[NSBundle mainBundle] pathForResource:PACK_NAME ofType:PACK_EXTENSION];
        NSData *data = path ? [NSData dataWithContentsOfFile:path options:NSDataReadingMappedAlways error:NULL] : nil;
        const uint8_t *bytes = data.bytes;
        uint32_t count = 0;
        if (data.length >= PACK_HEADER && !memcmp(bytes, "EXEM", 4)) memcpy(&count, bytes + 4, 4);
        /* the pack and the table are generated together, a different count is a stale file */
        if (count == exteria_emoji_image_count && data.length >= PACK_HEADER + 8u * count) pack = [data retain];
        else NSLog(@"exteria: emoji picture pack is missing or does not match the table");
    });
    return pack;
}

static NSCache *ExteriaEmojiCache(void) {
    static NSCache *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [[NSCache alloc] init];
        cache.countLimit = 128;
        cache.totalCostLimit = 4 * 1024 * 1024;
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:nil usingBlock:^(NSNotification *note) {
            (void)note;
            [cache removeAllObjects];
        }];
    });
    return cache;
}

static const exteria_emoji_entry *ExteriaEmojiEntry(size_t index) {
    if (index >= exteria_emoji_entry_count) return NULL;
    const exteria_emoji_entry *entry = &exteria_emoji_entries[index];
    return entry->image == EXTERIA_EMOJI_NO_IMAGE ? NULL : entry;
}

/* nil when the record points outside the file */
static NSData *ExteriaEmojiBytes(uint16_t image) {
    NSData *pack = ExteriaEmojiPack();
    if (!pack) return nil;
    uint32_t offset, length;
    const uint8_t *bytes = pack.bytes;
    memcpy(&offset, bytes + PACK_HEADER + 8u * image, 4);
    memcpy(&length, bytes + PACK_HEADER + 8u * image + 4, 4);
    if ((uint64_t)offset + length > pack.length) return nil;
    return [NSData dataWithBytesNoCopy:(void *)(bytes + offset) length:length freeWhenDone:NO];
}

/* a picture that does not decode is not asked for again, or every redraw would queue it */
static NSMutableSet *ExteriaEmojiFailed(void) {
    static NSMutableSet *failed;
    if (!failed) failed = [[NSMutableSet alloc] init];
    return failed;
}

BOOL ExteriaEmojiHasPicture(size_t index) {
    const exteria_emoji_entry *entry = ExteriaEmojiEntry(index);
    if (!entry || !ExteriaEmojiPack()) return NO;
    return ![ExteriaEmojiFailed() containsObject:[NSNumber numberWithUnsignedShort:entry->image]];
}

static NSMutableArray *sWaiting;
static NSMutableSet *sPending;
static NSUInteger sLoadedSinceRedraw;
static NSUInteger sMisses;

static void ExteriaEmojiRedrawWaiting(void) {
    NSArray *views = [sWaiting copy];
    [sWaiting removeAllObjects];
    sLoadedSinceRedraw = 0;
    for (UIView *view in views) [view setNeedsDisplay];
    [views release];
}

static void ExteriaEmojiDecoded(NSNumber *key, UIImage *image) {
    if (image) [ExteriaEmojiCache() setObject:image forKey:key];
    else {
        NSLog(@"exteria: emoji picture %@ does not decode", key);
        [ExteriaEmojiFailed() addObject:key];
    }
    [sPending removeObject:key];
    ++sLoadedSinceRedraw;
    /* waits for the queue to run dry, so a screenful of emoji repaints once and not per picture */
    if (!sPending.count || sLoadedSinceRedraw >= 16) ExteriaEmojiRedrawWaiting();
}

static UIImage *PKFitEmojiImage(UIImage *image) {
    CGImageRef original = image.CGImage;
    if (!original) return image;
    size_t width = CGImageGetWidth(original), height = CGImageGetHeight(original);
    if (!width || !height || width > 512 || height > 512) return image;
    size_t stride = width * 4, bounds[4];
    uint8_t *pixels = calloc(height, stride);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = pixels && space ? CGBitmapContextCreate(pixels, width, height, 8, stride, space,
        kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big) : NULL;
    if (space) CGColorSpaceRelease(space);
    if (!context) { free(pixels); return image; }
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), original);
    BOOL fitted = exteria_emoji_alpha_bounds(pixels, height * stride, width, height, stride, bounds);
    CGImageRef bitmap = fitted ? CGBitmapContextCreateImage(context) : NULL;
    CGContextRelease(context); free(pixels);
    CGImageRef cropped = bitmap ? CGImageCreateWithImageInRect(bitmap, CGRectMake(bounds[0], bounds[1], bounds[2], bounds[3])) : NULL;
    if (bitmap) CGImageRelease(bitmap);
    if (!cropped) return image;
    CGFloat side = MAX(width, height), scale = side * 0.93 / MAX(bounds[2], bounds[3]);
    CGSize shown = CGSizeMake(bounds[2] * scale, bounds[3] * scale);
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(side, side), NO, 1);
    [[UIImage imageWithCGImage:cropped] drawInRect:CGRectMake((side - shown.width) / 2, (side - shown.height) / 2, shown.width, shown.height)];
    UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext(); CGImageRelease(cropped);
    return result ? result : image;
}


/* font bitmaps have different transparent margins */
static UIImage *ExteriaDecodeEmoji(NSData *data, uint8_t group) {
    UIImage *image = PKDecodeWebP(data);
    /* cropping would enlarge small squares, flags and kneeling figures past their font metrics */
    if (group == 1 || group >= 7) return image;
    return PKFitEmojiImage(image);
}

static void ExteriaEmojiSchedule(NSNumber *key, NSData *data, uint8_t group) {
    static dispatch_queue_t queue;
    if (!queue) {
        queue = dispatch_queue_create("exteria.emoji.decode", DISPATCH_QUEUE_SERIAL);
        sPending = [[NSMutableSet alloc] init];
        sWaiting = [[NSMutableArray alloc] init];
    }
    if ([sPending containsObject:key]) return;
    [sPending addObject:key];
    dispatch_async(queue, ^{
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        UIImage *image = ExteriaDecodeEmoji(data, group);
        dispatch_async(dispatch_get_main_queue(), ^{ ExteriaEmojiDecoded(key, image); });
        [pool drain];
    });
}

UIImage *ExteriaEmojiImage(size_t index) {
    const exteria_emoji_entry *entry = ExteriaEmojiEntry(index);
    if (!entry) return nil;
    NSNumber *key = [NSNumber numberWithUnsignedShort:entry->image];
    UIImage *image = [ExteriaEmojiCache() objectForKey:key];
    if (image || [ExteriaEmojiFailed() containsObject:key]) return image;
    NSData *data = ExteriaEmojiBytes(entry->image);
    if (!data) return nil;
    ExteriaEmojiSchedule(key, data, entry->group);
    ++sMisses;
    return nil;
}

UIImage *ExteriaEmojiImageNow(size_t index) {
    const exteria_emoji_entry *entry = ExteriaEmojiEntry(index);
    if (!entry) return nil;
    NSNumber *key = [NSNumber numberWithUnsignedShort:entry->image];
    UIImage *image = [ExteriaEmojiCache() objectForKey:key];
    if (image) return image;
    NSData *data = ExteriaEmojiBytes(entry->image);
    image = data ? ExteriaDecodeEmoji(data, entry->group) : nil;
    if (image) [ExteriaEmojiCache() setObject:image forKey:key];
    return image;
}

NSUInteger ExteriaEmojiMissCount(void) { return sMisses; }

void ExteriaEmojiRedrawWhenLoaded(UIView *view) {
    if (!sWaiting || !sPending.count) return;
    if ([sWaiting indexOfObjectIdenticalTo:view] == NSNotFound) [sWaiting addObject:view];
}

NSString *ExteriaEmojiString(size_t entry) {
    uint16_t units[32];
    size_t count = exteria_emoji_encode(entry, units, 32);
    return count ? [NSString stringWithCharacters:units length:count] : @"";
}

void ExteriaDrawEmoji(size_t entry, CGRect rect) {
    UIImage *image = ExteriaEmojiImage(entry);
    if (image) [image drawInRect:rect];
}
