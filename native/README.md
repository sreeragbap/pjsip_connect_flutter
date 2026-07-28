# native/ — building the PJSIP engine

This directory replaces the previous closed-source engine binaries with a cross-compiled
**PJSIP** engine. The scripts run on **your machine** (they need network access
and the NDK/Xcode toolchains — they can't run in CI sandboxes).

## One-time build

```bash
# Android (produces android/src/main/jniLibs/<abi>/libpjsua2.so + Java binding)
export ANDROID_NDK_ROOT="$HOME/Library/Android/sdk/ndk/26.3.11579264"
./build-android.sh

# iOS (produces ios/pjsip_connect_flutter/pjsip.xcframework + pjsip-headers/)
./build-ios.sh
```

Expect the first build to take a while (PJSIP + all modules, four Android ABIs
and three iOS slices). Rebuild only when `VERSIONS.md` or `config_site.h` change.

## What the scripts do

1. Fetch the pinned pjproject tag (see `VERSIONS.md`).
2. Copy `config_site.h` into the PJSIP tree (single source of build knobs).
3. Cross-compile per ABI / per iOS slice.
4. Android: build the `pjsua2` SWIG Java binding (`org.pjsip.pjsua2.*`) + `.so`.
   iOS: merge static libs and assemble `pjsip.xcframework`.

## After building

- `native/` and `.work*/` are build-time only — add them to `.gitignore`, and
  commit the produced `jniLibs/` + `pjsip.xcframework` (or host them in your
  artifact store) the same way the old engine binaries were vendored.
- The plugin's `build.gradle` / podspec are wired to consume these outputs (see
  `../ENGINE_REPLACEMENT_PLAN.md` P0). The old engine AAR/xcframeworks are
  removed in that step.

## License reminder

PJSIP is GPLv2-or-commercial. Using these unmodified GPL builds obliges you to
offer your app's source under GPL **if you distribute it**. See the plan doc §2.
