#ifndef PK_STATUS_H
#define PK_STATUS_H

/* callers act differently: a malformed page is reported, a missing element is normal, a truncated field
   still has bytes */
typedef enum {
    PK_OK = 0,
    PK_ERR_INVALID,    /* the bytes do not parse as the shape asked for */
    PK_ERR_NOT_FOUND,  /* the element or attribute is simply absent */
    PK_ERR_TRUNCATED,  /* the value did not fit the caller's buffer */
    PK_ERR_TOO_LARGE   /* the input crossed a hard bound and was not read */
} pk_status;

/* story pages stay well under a megabyte, anything bigger is refused */
#define PK_MAX_DOCUMENT_BYTES (4u * 1024u * 1024u)

#endif
