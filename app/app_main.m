#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import "main_vc.h"
#import "login_vc.h"
#import "pk_auth.h"
#import "pk_theme.h"

@interface PKAppDelegate : UIResponder <UIApplicationDelegate> { UIWindow *_window; }
@property(nonatomic, retain) UIWindow *window;
@end
@implementation PKAppDelegate
@synthesize window = _window;
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options {
    (void)application;
    (void)options;
    self.window = [[[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]] autorelease];
    self.window.backgroundColor = PKBackgroundColor();
    self.window.rootViewController = PKRootViewController();
    PKApplyGlobalTheme();
    [self.window makeKeyAndVisible];
    [self verifyStoredSession];
    return YES;
}
/* the flag outlives the cookies, and a reader who looks signed in would fail every vote */
- (void)verifyStoredSession {
    if (PKSessionWasAuthenticated()) PKCheckSession(nil);
}
- (void)applicationWillEnterForeground:(UIApplication *)application {
    (void)application;
    [self verifyStoredSession];
}
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 90000
- (UIInterfaceOrientationMask)application:(UIApplication *)application
#else
- (NSUInteger)application:(UIApplication *)application
#endif
 supportedInterfaceOrientationsForWindow:(UIWindow *)window {
    (void)application;
    (void)window;
/* an ipad is held every way round, a phone is not held upside down */
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
        return UIInterfaceOrientationMaskAll;
    return UIInterfaceOrientationMaskAllButUpsideDown;
}
- (void)dealloc { [_window release]; [super dealloc]; }
@end

int main(int argc, char *argv[]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int result = UIApplicationMain(argc, argv, nil, @"PKAppDelegate");
    [pool release];
    return result;
}
