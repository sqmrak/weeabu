#import <UIKit/UIKit.h>

typedef void (^PKImageCompletion)(UIImage *image);
void PKClearImageCache(void);
void PKLoadImage(NSString *urlString, PKImageCompletion completion);
NSString *PKLegacyImageURL(NSString *urlString);

UIImage *PKDecodeWebP(NSData *data);
