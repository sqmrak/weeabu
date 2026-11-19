#import <Foundation/Foundation.h>

typedef void (^PKHTTPCompletion)(NSData *data, NSError *error);

NSString *PKHTTPPercentEncode(NSString *value);
/* cp1251 only for the few endpoints still on it */
NSString *PKHTTPText(NSData *data);

void PKHTTPGet(NSString *urlString, PKHTTPCompletion completion);
void PKHTTPPost(NSString *urlString, NSDictionary *fields, NSString *csrfToken, PKHTTPCompletion completion);

void PKHTTPPostV1(NSString *method, NSData *body, NSString *deviceID, PKHTTPCompletion completion);
