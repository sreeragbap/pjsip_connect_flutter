# Changelog

## 1.0.1

- iOS: fixed PushKit wake-up — a VoIP push now restarts SIP transports and
  refreshes registrations (`handleIpChange`), so the INVITE reaches a
  suspended/killed app
- Added [iOS Call Setup Guide](doc/ios_call_setup.md) and
  [iOS Backend Configuration Guide](doc/ios_backend_setup.md)
- Replaced the license file with the plugin's MIT license (bundled PJSIP
  binaries remain GPLv2/commercial — see README)
- Fixed static-analysis lints (dangling doc comments, non-constant
  identifier names)

## 1.0.0

Initial release.

- SIP registration over UDP/TCP/TLS 1.3 with automatic re-register on network
  change (PJSIP 2.15.1 engine, prebuilt for Android and iOS)
- Audio calls: place/receive, hold, blind & attended transfer, mute, DTMF,
  call recording, file/tone playback, conference mixer
- SDES-SRTP media encryption and ICE
- SIP MESSAGE instant messaging and presence subscriptions
- iOS CallKit integration; Android foreground service with incoming-call
  notifications
- `ChangeNotifier` models for accounts, calls, messages, devices, network
  state, CDRs, and logs
- iOS builds via both CocoaPods and Swift Package Manager
