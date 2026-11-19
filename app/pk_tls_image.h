#ifndef PK_TLS_IMAGE_H
#define PK_TLS_IMAGE_H

#import <Foundation/Foundation.h>

/* both check the bundled roots, hostname and dates and refuse a url outside pikabu.ru. used when ios 5 and
   6 cfnetwork cannot finish the cdn handshake */

NSData *PKTLSImageGet(NSString *urlString, NSError **error);

/* for a public v1 request after old cfnetwork rejects the current trust chain */
NSData *PKTLSV1Post(NSString *method, NSData *body, NSString *deviceID, NSError **error);

/* holding a whole video makes an old device kill the app */
BOOL PKTLSVideoDownload(NSString *urlString, int fd, NSError **error);

#endif
