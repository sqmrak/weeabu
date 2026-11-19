#import <Foundation/Foundation.h>

typedef void (^PKAuthCompletion)(BOOL authenticated, NSString *username, NSError *error);
typedef void (^PKSignOutCompletion)(NSError *error);

void PKSignIn(NSString *username, NSString *password, PKAuthCompletion completion);
/* a transport failure says nothing about the session, so the stored state stays */
void PKCheckSession(PKAuthCompletion completion);
/* signed out whatever the answer, the error only says the site did not confirm it */
void PKSignOut(PKSignOutCompletion completion);
BOOL PKSessionWasAuthenticated(void);
NSString *PKSessionUsername(void);
/* nil for a session opened before it was kept, PKCheckSession refreshes it */
NSNumber *PKSessionUserID(void);
