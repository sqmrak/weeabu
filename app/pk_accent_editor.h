#import <UIKit/UIKit.h>
@interface PKAccentEditor : UIControl <UITextFieldDelegate>
@property(nonatomic, assign) float hue;
@property(nonatomic, assign) float saturation;
@property(nonatomic, assign) float brightness;
@property(nonatomic, readonly) CGFloat preferredHeight;
@property(nonatomic, readonly) CGRect editingRect;
@end
