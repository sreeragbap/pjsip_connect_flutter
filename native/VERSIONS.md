# Pinned native toolchain versions

These are the exact versions the build scripts fetch/use. Bump deliberately and
re-run the full build so the produced binaries stay reproducible.

| Component | Version | Why pinned |
|---|---|---|
| pjproject (PJSIP) | **2.15.1** | SIP + media engine (pjsua2 API) |
| OpenSSL | **3.3.2** | TLS transport + DTLS-SRTP (static, per ABI/slice) |
| Android NDK | **26.3.11579264** (r26d) | Stable LTS; PJSIP builds clean |
| Android min API | **21** | Matches the plugin's `minSdkVersion` |
| Android ABIs | armeabi-v7a, arm64-v8a, x86, x86_64 | Same 4 the old engine AAR shipped |
| iOS min | **14.0** | Matches the podspec floor |
| iOS slices | device arm64, simulator arm64+x86_64 | Same as the removed xcframeworks |
| Opus | 1.5.2 | Added in P3 (not in the P0 build) |

## Codecs in the P0 build

P0 uses only PJSIP's **bundled, license-clean** codecs so the first build has no
extra dependencies: **PCMU (G.711µ), PCMA (G.711a), G.722, iLBC, GSM, Speex**.
Opus (and optionally G.729) are layered in at P3.

Note: our Dart `Codec` list still advertises Opus/iSAC/etc. because those enum
values are the wire contract. Until P3, selecting an unbuilt codec simply won't
be negotiated — it does not break the protocol.

## License

pjproject is **GPLv2 or commercial**. This repo's use is under GPLv2 unless you
hold a PJSIP commercial license. See `../ENGINE_REPLACEMENT_PLAN.md` §2.
