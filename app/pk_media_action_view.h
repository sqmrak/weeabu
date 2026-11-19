#import <UIKit/UIKit.h>

typedef enum {
    PKMediaIconPlay,
    PKMediaIconPause,
    PKMediaIconDownload,
    PKMediaIconCancel,
    PKMediaIconFile,
    PKMediaIconNone
} PKMediaIcon;

@interface PKMediaActionView : UIView

@property (nonatomic, retain) UIColor *discColor;
@property (nonatomic, retain) UIColor *inkColor;
@property (nonatomic, readonly) PKMediaIcon icon;

- (void)setIcon:(PKMediaIcon)icon animated:(BOOL)animated;
- (void)setProgress:(float)progress;

@end
