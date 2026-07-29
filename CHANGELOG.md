# Changelog

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
