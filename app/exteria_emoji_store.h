#import <UIKit/UIKit.h>

#include "exteria_emoji.h"

/* the layout needs it to reserve room */
BOOL ExteriaEmojiHasPicture(size_t entry);

UIImage *ExteriaEmojiImage(size_t entry);

/* for bitmaps that are kept, where a missing picture cannot be filled in later */
UIImage *ExteriaEmojiImageNow(size_t entry);

/* nil when this ios cannot draw the complete sequence */
void ExteriaLargeEmojiImage(size_t entry, void (^completion)(UIImage *image));

/* a view reads it before and after drawing and calls ExteriaEmojiRedrawWhenLoaded when it changed */
NSUInteger ExteriaEmojiMissCount(void);

/* asking twice before the redraw is the same as once */
void ExteriaEmojiRedrawWhenLoaded(UIView *view);

NSString *ExteriaEmojiString(size_t entry);

/* leaves the rect empty while the picture decodes */
void ExteriaDrawEmoji(size_t entry, CGRect rect);
