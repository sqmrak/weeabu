#ifndef PK_URL_H
#define PK_URL_H

#include <stddef.h>

#include "pk_span.h"
#include "pk_status.h"

/* longer urls are refused, a truncated one points somewhere else */
#define PK_MAX_URL_BYTES 1024

/* anything that is not an https url with a host, no userinfo and no control bytes is PK_ERR_INVALID, so
   callers only get urls the network layer may fetch */
pk_status pk_url_normalize(const char *raw, size_t length,
                           char *out, size_t capacity, size_t *written);

/* for a link the reader taps: it leaves for the system browser, so plain http and any host are fine, the
   other rules hold */
pk_status pk_url_normalize_link(const char *raw, size_t length,
                                char *out, size_t capacity, size_t *written);

pk_status pk_url_host(const char *url, size_t length, pk_span *host);

#endif
