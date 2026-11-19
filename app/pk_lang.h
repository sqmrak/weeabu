#import <Foundation/Foundation.h>

/* a missing entry falls back to the russian source, so a new string works before it is translated */
NSString *PKText(NSString *russian);

BOOL PKEnglishEnabled(void);
void PKSetEnglishEnabled(BOOL enabled);
NSString *PKLanguageName(void);
