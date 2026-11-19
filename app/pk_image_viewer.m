#import "pk_image_viewer.h"
@implementation PKImageViewerViewController
- (id)initWithURL:(NSString *)url title:(NSString *)title {
    return [self initWithImageURLs:[NSArray arrayWithObject:url ?: @""] title:title index:0];
}
- (id)initWithURLs:(NSArray *)urls title:(NSString *)title index:(NSUInteger)index {
    return [self initWithImageURLs:urls title:title index:index];
}
@end
