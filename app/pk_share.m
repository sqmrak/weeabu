#import "pk_share.h"
#import "pk_dialog.h"
#import "pk_lang.h"

void PKPresentShareSheet(UIView *host, NSString *title, NSString *url) {
    (void)host;
    if (!url.length) return;
    NSString *link = [[url copy] autorelease];
    PKShowSheet(title, [NSArray arrayWithObjects:PKText(@"Скопировать ссылку"), PKText(@"Открыть в Safari"), nil], -1, nil, ^(NSInteger index) {
        if (index == 0) {
            [UIPasteboard generalPasteboard].string = link;
        } else if (index == 1) {
            NSURL *target = [NSURL URLWithString:link];
            if (target) [[UIApplication sharedApplication] openURL:target];
        }
    });
}
