#import <UIKit/UIKit.h>

extern NSString * const PKThemeDidChangeNotification;

/* a cache of anything drawn in the palette or worded in the language empties itself when this differs from
   the value it was filled under */
NSUInteger PKThemeRevision(void);
/* posts the notification after the counter moves, so a redrawing screen sees the new revision */
void PKPostThemeChange(void);

/* the palette pikabu.ru ships in its own stylesheet */
void PKGetAccent(float *hue, float *saturation, float *brightness);
void PKSetAccent(float hue, float saturation, float brightness);
void PKResetAccent(void);
UIColor *PKAccentColor(void);
UIColor *PKAccentFillColor(void);
UIColor *PKOrangeColor(void);
UIColor *PKDangerColor(void);
UIColor *PKBackgroundColor(void);
UIColor *PKCardColor(void);
UIColor *PKBarColor(void);
UIColor *PKBarContentColor(void);
UIColor *PKTextColor(void);
UIColor *PKMutedColor(void);
UIColor *PKSeparatorColor(void);
UIColor *PKHairlineColor(void);
UIColor *PKMediaWellColor(void);
/* the page color, so a pill reads as a dent in the card */
UIColor *PKControlColor(void);
BOOL PKDarkThemeEnabled(void);
void PKSetDarkThemeEnabled(BOOL enabled);
NSInteger PKDefaultFeedIndex(void);
void PKSetDefaultFeedIndex(NSInteger index);
BOOL PKCollapseCommentBranchesEnabled(void);
void PKSetCollapseCommentBranchesEnabled(BOOL enabled);
void PKApplyGlobalTheme(void);

/* a bundle that lost the files still draws the system font */
typedef enum {
    PKFontWeightRegular = 0,
    PKFontWeightMedium,
    PKFontWeightBold
} PKFontWeight;
UIFont *PKFont(PKFontWeight weight, CGFloat size);

/* the bar color is a different property before ios 7 and the appearance proxy never reaches live views, so
   every live bar is restyled here */
void PKStyleNavigationBar(UINavigationBar *bar);
void PKStyleTabBar(UITabBar *bar);
void PKStyleSearchBar(UISearchBar *bar);
UIActivityIndicatorViewStyle PKSpinnerStyle(void);

/* past the readable width a card turns into a banner, so an ipad gets margin */
CGFloat PKContentWidth(CGFloat width);
CGFloat PKContentSideInset(CGFloat width);
CGFloat PKCardCornerRadius(CGFloat width);

/* the table spans the whole host so the bars reach both ipad edges, and the row narrows itself */
@interface PKReadableCell : UITableViewCell
@end

UIColor *PKSectionTitleColor(void);
UIView *PKSectionHeader(NSString *title, CGFloat width, CGFloat height);
void PKStyleTable(UITableView *tableView);
UILabel *PKLabel(CGFloat size, UIColor *color, BOOL bold);
