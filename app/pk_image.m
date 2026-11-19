#import "pk_image.h"
#import <ImageIO/ImageIO.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import "src/webp/decode.h"
#import "pk_tls_image.h"
#import "pk_tls_rules.h"

static const NSUInteger PKMaximumImageBytes = 24 * 1024 * 1024;
static const CGFloat PKMaximumImagePixels = 960;
static const NSUInteger PKMaximumWebPPixels = 24 * 1024 * 1024;
static const NSUInteger PKMaximumGIFFrames = 60;
static const NSUInteger PKMaximumGIFPixels = 12 * 1024 * 1024;

/* a 960 px preview is about 2.4 MB, so a count limit alone let the cache pass 150 MB on a 512 MB phone and
   the system killed the app without a crash report */
static const NSUInteger PKImageCacheBytes = 32 * 1024 * 1024;

static NSCache *PKImageCache(void) {
    static NSCache *cache;
    if (!cache) {
        cache = [[NSCache alloc] init];
        cache.countLimit = 80;
        cache.totalCostLimit = PKImageCacheBytes;
/* ios 5 does not trim an NSCache on its own */
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
                                                          object:nil queue:nil
                                                      usingBlock:^(NSNotification *note) {
            (void)note;
            [cache removeAllObjects];
        }];
    }
    return cache;
}

void PKClearImageCache(void) {
    [PKImageCache() removeAllObjects];
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
}

static void PKCacheImage(UIImage *image, NSString *key) {
    if (!image || !key.length) return;
    NSUInteger frames = MAX((NSUInteger)1, image.images.count);
    NSUInteger cost = (NSUInteger)(image.size.width * image.scale * image.size.height * image.scale * 4.0) * frames;
    [PKImageCache() setObject:image forKey:key cost:cost];
}

static NSOperationQueue *PKImageQueue(void) {
    static NSOperationQueue *queue;
    if (!queue) {
        queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = 3;
    }
    return queue;
}

static UIImage *PKThumbnailFromData(NSData *data) {
    if (!data.length || data.length > PKMaximumImageBytes) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)data, NULL);
    if (!source) return nil;
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
        (id)kCFBooleanTrue, (id)kCGImageSourceCreateThumbnailFromImageAlways,
        (id)kCFBooleanTrue, (id)kCGImageSourceCreateThumbnailWithTransform,
        [NSNumber numberWithFloat:PKMaximumImagePixels], (id)kCGImageSourceThumbnailMaxPixelSize,
        nil];
    CGImageRef imageRef = CGImageSourceCreateThumbnailAtIndex(source, 0, (CFDictionaryRef)options);
    CFRelease(source);
    if (!imageRef) return nil;
    UIImage *image = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);
    return image;
}

static NSTimeInterval PKGIFFrameDelay(CGImageSourceRef source, NSUInteger index) {
    NSTimeInterval delay = 0.1;
    CFDictionaryRef properties = CGImageSourceCopyPropertiesAtIndex(source, index, NULL);
    if (properties) {
        NSDictionary *gif = [(NSDictionary *)properties objectForKey:(id)kCGImagePropertyGIFDictionary];
        NSNumber *value = [gif objectForKey:(id)kCGImagePropertyGIFUnclampedDelayTime];
        if (![value isKindOfClass:[NSNumber class]]) value = [gif objectForKey:(id)kCGImagePropertyGIFDelayTime];
        if ([value isKindOfClass:[NSNumber class]] && [value doubleValue] >= 0.02) delay = [value doubleValue];
        CFRelease(properties);
    }
    return delay;
}

static UIImage *PKAnimatedGIFThumbnailFromData(NSData *data) {
    if (!data.length || data.length > PKMaximumImageBytes) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithData((CFDataRef)data, NULL);
    if (!source) return nil;
    CFStringRef type = CGImageSourceGetType(source);
    NSUInteger count = CGImageSourceGetCount(source);
    if (!type || !UTTypeConformsTo(type, CFSTR("com.compuserve.gif")) || count < 2 || count > PKMaximumGIFFrames) {
        CFRelease(source);
        return nil;
    }
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
        (id)kCFBooleanTrue, (id)kCGImageSourceCreateThumbnailFromImageAlways,
        (id)kCFBooleanTrue, (id)kCGImageSourceCreateThumbnailWithTransform,
        [NSNumber numberWithFloat:PKMaximumImagePixels], (id)kCGImageSourceThumbnailMaxPixelSize, nil];
    NSMutableArray *frames = [NSMutableArray arrayWithCapacity:count];
    NSUInteger totalPixels = 0;
    NSTimeInterval duration = 0;
    NSUInteger index;
    for (index = 0; index < count; index++) {
        CGImageRef imageRef = CGImageSourceCreateThumbnailAtIndex(source, index, (CFDictionaryRef)options);
        if (!imageRef) continue;
        NSUInteger width = CGImageGetWidth(imageRef), height = CGImageGetHeight(imageRef);
        if (height && (width > PKMaximumGIFPixels / height || totalPixels > PKMaximumGIFPixels - width * height)) {
            CGImageRelease(imageRef);
            [frames removeAllObjects];
            break;
        }
        totalPixels += width * height;
        [frames addObject:[UIImage imageWithCGImage:imageRef]];
        duration += PKGIFFrameDelay(source, index);
        CGImageRelease(imageRef);
    }
    CFRelease(source);
    if (frames.count < 2) return nil;
    return [UIImage animatedImageWithImages:frames duration:MAX(duration, 0.1)];
}

static void PKReleaseWebPData(void *info, const void *data, size_t size) {
    (void)info;
    (void)size;
    free((void *)data);
}

UIImage *PKDecodeWebP(NSData *data) {
    int sourceWidth = 0;
    int sourceHeight = 0;
    if (!data.length || data.length > PKMaximumImageBytes ||
        !WebPGetInfo(data.bytes, data.length, &sourceWidth, &sourceHeight) ||
        sourceWidth <= 0 || sourceHeight <= 0) return nil;
    if ((NSUInteger)sourceWidth > PKMaximumWebPPixels / (NSUInteger)sourceHeight) return nil;

    CGFloat scale = MIN(1.0, PKMaximumImagePixels / MAX(sourceWidth, sourceHeight));
    int width = MAX(1, (int)(sourceWidth * scale));
    int height = MAX(1, (int)(sourceHeight * scale));
    if ((NSUInteger)width > SIZE_MAX / 4 || (NSUInteger)height > SIZE_MAX / ((NSUInteger)width * 4)) return nil;
    size_t stride = (size_t)width * 4;
    size_t bytes = stride * (size_t)height;
    uint8_t *pixels = malloc(bytes);
    if (!pixels) return nil;

    WebPDecoderConfig config;
    if (!WebPInitDecoderConfig(&config)) {
        free(pixels);
        return nil;
    }
    config.output.colorspace = MODE_RGBA;
    config.output.u.RGBA.rgba = pixels;
    config.output.u.RGBA.stride = (int)stride;
    config.output.u.RGBA.size = bytes;
    config.output.is_external_memory = 1;
    config.options.use_scaling = width != sourceWidth || height != sourceHeight;
    config.options.scaled_width = width;
    config.options.scaled_height = height;
    if (WebPDecode(data.bytes, data.length, &config) != VP8_STATUS_OK) {
        WebPFreeDecBuffer(&config.output);
        free(pixels);
        return nil;
    }
    WebPFreeDecBuffer(&config.output);

    CGDataProviderRef provider = CGDataProviderCreateWithData(NULL, pixels, bytes, PKReleaseWebPData);
    if (!provider) {
        free(pixels);
        return nil;
    }
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    if (!colorSpace) {
        CGDataProviderRelease(provider);
        return nil;
    }
    CGImageRef imageRef = CGImageCreate(width, height, 8, 32, stride, colorSpace,
        kCGImageAlphaLast | kCGBitmapByteOrderDefault, provider, NULL, NO, kCGRenderingIntentDefault);
    CGColorSpaceRelease(colorSpace);
    CGDataProviderRelease(provider);
    if (!imageRef) return nil;
    UIImage *image = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);
    return image;
}

NSString *PKLegacyImageURL(NSString *urlString) {
    if (!urlString.length) return nil;
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url || ![[url scheme] isEqualToString:@"https"] || ![[url host] length] ||
        !PKTLSHostAllowed([[[url host] lowercaseString] UTF8String])) return nil;
    return [url absoluteString];
}

void PKLoadImage(NSString *urlString, PKImageCompletion completion) {
    if (!urlString.length) {
        if (completion) completion(nil);
        return;
    }
    UIImage *cached = [PKImageCache() objectForKey:urlString];
    if (cached) {
        if (completion) completion(cached);
        return;
    }
    NSURL *url = [NSURL URLWithString:PKLegacyImageURL(urlString)];
    if (!url) {
        if (completion) completion(nil);
        return;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:NSURLRequestReturnCacheDataElseLoad timeoutInterval:20.0];
    [request setValue:@"image/jpeg,image/png,image/gif,image/webp" forHTTPHeaderField:@"Accept"];
    [NSURLConnection sendAsynchronousRequest:request queue:PKImageQueue() completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
        if (error) {
            // ios 5 and 6 cfnetwork cannot do the tls the current pikabu cdn offers
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
                NSError *tlsError = nil;
                NSData *tlsData = PKTLSImageGet(url.absoluteString, &tlsError);
                UIImage *tlsImage = PKDecodeWebP(tlsData) ?: PKAnimatedGIFThumbnailFromData(tlsData) ?: PKThumbnailFromData(tlsData);
                if (tlsImage) PKCacheImage(tlsImage, urlString);
                else NSLog(@"Pikabu image TLS fallback failed: %@", tlsError);
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(tlsImage); });
                [pool drain];
            });
            return;
        }
        UIImage *image = !error ? (PKDecodeWebP(data) ?: PKAnimatedGIFThumbnailFromData(data) ?: PKThumbnailFromData(data)) : nil;
        if (!image && !error) {
            NSString *type = [(NSHTTPURLResponse *)response MIMEType] ?: @"unknown";
            NSLog(@"Pikabu image decode failed (%@, %lu bytes): %@", type, (unsigned long)data.length, urlString);
        }
        PKCacheImage(image, urlString);
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(image); });
    }];
}
