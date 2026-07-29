# pjsip_connect_flutter

Flutter VoIP/SIP plugin for Android and iOS — voice/video calls, messaging,
and BLF/presence subscriptions, built on a cross-compiled
[PJSIP](https://www.pjsip.org) 2.15.1 engine (bundled as prebuilt binaries,
no extra native setup required).

## Features

- SIP registration over UDP / TCP / **TLS 1.3**, with automatic re-register on
  network/IP change
- Audio calls: place, receive, hold, transfer (blind & attended), mute,
  DTMF (send/receive), call recording and file/tone playback
- SRTP media encryption (SDES) and ICE
- Conference / call switching via the built-in audio mixer
- SIP MESSAGE-based instant messaging
- Presence subscriptions (SUBSCRIBE/NOTIFY)
- iOS **CallKit** integration; Android foreground service with incoming-call
  notifications
- `ChangeNotifier`-based models (`AccountsModel`, `CallsModel`,
  `MessagesModel`, `DevicesModel`, `NetworkModel`, `CdrsModel`, …) that plug
  straight into `provider`-style state management
- Complete example app demonstrating accounts, calls, messaging, and
  subscriptions

## Platform support

| Platform | Minimum | Notes |
|---|---|---|
| Android | as declared in `android/build.gradle` | arm64-v8a, armeabi-v7a, x86_64, x86 |
| iOS | as declared in the podspec | CocoaPods and Swift Package Manager |

## Getting started

Add the dependency:

```yaml
dependencies:
  pjsip_connect_flutter: ^1.0.0
```

Initialize the engine and register an account:

```dart
import 'package:pjsip_connect_flutter/pjsip_connect_flutter.dart';

final logsModel = LogsModel(true);
final accountsModel = AccountsModel(logsModel);

// Initialize the engine once at startup.
await PjsipConnectFlutter.instance.initialize(InitData(), logsModel);

// Register a SIP account.
final account = AccountModel()
  ..sipServer = 'sip.example.com'
  ..sipExtension = '100'
  ..sipPassword = 'secret';
await accountsModel.addAccount(account);
```

See [`example/`](example/) for a full application covering calls, hold,
transfer, DTMF, messaging, and presence subscriptions.

## License

This plugin bundles PJSIP, which is licensed under the
**GNU General Public License v2** (or a commercial license available from
Teluu). Consequently this package is distributed under **GPL-2.0** — see
[LICENSE](LICENSE).

In practice this means apps that distribute this plugin must either comply
with the GPL (make their source available under a GPL-compatible license) or
obtain a [commercial PJSIP license](https://www.pjsip.org/licensing.htm).
