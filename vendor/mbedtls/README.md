# mbedtls 3.6.4

This directory vendors the headers and armv7/arm64 static libraries from
`/home/sqmrak/Samsung/cache/senko/mbedtls-ios-3.6.4` at integration time.
Pikabu links these local files directly and has no runtime dependency on Senko
or any other project. `LICENSE` is the upstream Apache-2.0 license.

`pikabu-ca.pem` contains ISRG Root X1, fetched from
`https://letsencrypt.org/certs/isrgrootx1.pem` on 2026-09-05. The live
`pikabu.ru` chain inspected at that time was `new.pikabu.ru`, Let's Encrypt
YR1, ISRG Root YR, ISRG Root X1. The root SHA-256 fingerprint is
`96:BC:EC:06:26:49:76:F3:74:60:77:9A:CF:28:C5:A7:CF:E8:A3:C0:AA:E1:1A:8F:FC:EE:05:C0:BD:DF:08:C6`.
