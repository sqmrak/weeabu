#import "pk_media_viewer.h"
@interface PKImageViewerViewController : PKMediaViewer
- (id)initWithURL:(NSString *)url title:(NSString *)title;
- (id)initWithURLs:(NSArray *)urls title:(NSString *)title index:(NSUInteger)index;
@end
