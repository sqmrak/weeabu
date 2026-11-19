# weeabu

native pikabu for old iphones and ipads, ios 5 and up, one deb

> [!NOTE]
> the deb is signed with ldid, so it needs a jailbreak.

## devices

- ios 5-6: armv7
- ios 7 and later: armv7, arm64
- iphone and ipad, one binary with both slices

## features

- feeds, search, posts, comments
- login, voting, reactions, replies, account settings
- media viewer for photos, video and gif
- material you look: spring motion, light and dark themes, your own accent color
- ipad layout
- russian, english

unofficial client, not affiliated with pikabu.

## install

```bash
meow install --host <device-ip> --legacy weeabu-v*.deb
```

or copy the deb over and run `dpkg -i`. remove: `dpkg -r ru.sqmrak.weeabu`

## build

built with meow by sqmrak, https://github.com/sqmrak/meow

```bash
meow doctor         # what it found: toolchain, sdks
meow test           # host tests of core/
meow build deb      # tests, both slices, release checks, weeabu-v<version>.deb
meow build ipa      # Weeabu-v<version>.ipa
```

the armv7 slice needs an sdk with `usr/lib/crt1.3.1.o`, 8.1 has it and 10.3 does not. overrides:

- `PK_TC`: toolchain bin directory
- `PK_SDK_V7`, `PK_SDK_V64`: sdk per slice
- `PK_CRT_V7`: armv7 start file
- `PK_SDK_COMPAT`: older sdk for `meow build check-compat`, a syntax-only pass that catches an api ios 5 lacks

icons and launch images are committed. redraw them with `meow build icons-home icons-deb image-mascot launch-main` and the `glyphs-*` steps after the artwork changes. `tools/` refreshes the fonts and the test fixtures from pikabu.ru.

## layout

- `core/`: portable c99, html and url parsers, spring and zoom math
- `app/`: uikit, manual reference counting
- `tests/`: host tests for `core/`
- `vendor/`: libwebp, mbedtls, pinned roots
- `meow.toml`: the whole build

the emoji image pack is not included: `resources/emoji/emoji.pack` contains apple artwork that cannot be redistributed. packaging needs a separately obtained pack at that path, see `resources/emoji/NOTICE.txt`.
