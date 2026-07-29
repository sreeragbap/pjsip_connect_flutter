# pjsip_connect_flutter

Flutter VoIP/SIP plugin for Android and iOS — voice calls, instant messaging,
and presence subscriptions, built on a cross-compiled
[PJSIP](https://www.pjsip.org) 2.15.1 engine (bundled as prebuilt binaries,
no extra native setup required). Video calls and BLF are on the roadmap.

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

## Usage

The plugin is driven through `ChangeNotifier` models. Create them once at
startup and share them with your UI (e.g. via `provider`):

```dart
final logsModel     = LogsModel(true);
final accountsModel = AccountsModel(logsModel);
final callsModel    = CallsModel(accountsModel, logsModel);
final messagesModel = MessagesModel(accountsModel, logsModel);
```

### Make a call

```dart
// toExt, fromAccId, withVideo
final dest = CallDestination('101', account.myAccId, false);
await callsModel.invite(dest);
```

Optional extras on `CallDestination`:

```dart
final dest = CallDestination('101', account.myAccId, false)
  ..inviteTimeout = 30                          // seconds to wait for an answer
  ..xheaders = {'X-My-Header': 'value'}         // custom INVITE headers
  ..displName = 'Alice';                        // overrides the account display name
```

### Handle incoming calls

```dart
callsModel.onNewIncomingCall = () {
  final call = callsModel.firstWhere((c) => c.state == CallState.ringing);

  // Accept (false = audio-only) …
  call.accept(false);

  // … or decline.
  // call.reject();
};
```

### Hang up

```dart
await call.bye();
```

### Mute the microphone

```dart
await call.muteMic(true);   // mute
await call.muteMic(false);  // unmute
print(call.isMicMuted);
```

### Hold / resume

```dart
await call.hold();          // toggles: holds when active, resumes when held
print(call.holdState);      // HoldState.local / remote / localAndRemote / none
```

### Send DTMF

```dart
await call.sendDtmf('1234#');
```

### Transfer a call

```dart
// Blind transfer to another extension:
await call.transferBlind('102');

// Attended transfer: put the first call on hold, call the transfer target,
// then connect the two by call id:
await call.transferAttended(otherCall.myCallId);
```

### Record / play audio

```dart
await call.recordFile('/path/to/recording.mp3');
await call.stopRecordFile();

await call.playFile('/path/to/announcement.mp3');
await call.stopPlayFile();
```

### Multiple calls and conferencing

```dart
await callsModel.switchToCall(call.myCallId);  // switch active audio to a call
await callsModel.makeConference();             // join all calls in a conference
```

### Observe call state

`CallModel` is a `ChangeNotifier` — listen to it (or to `CallsModel` for the
whole list) and read:

```dart
call.state;       // dialing, proceeding, ringing, connected, …
call.remoteExt;   // remote extension / number
call.isIncoming;
call.duration;
```

See [`example/`](example/) for a full application covering calls, hold,
transfer, DTMF, messaging, and presence subscriptions.

## iOS: PushKit + CallKit integration

CallKit gives calls the native iOS call UI; PushKit (VoIP push) wakes the app
for incoming calls when it's killed or in the background.

**1. Xcode setup** — in your Runner target enable the capabilities
*Push Notifications* and *Background Modes → Voice over IP*, and upload a VoIP
Services certificate to your push gateway.

**2. Enable both in `InitData`** when initializing the engine:

```dart
final iniData = InitData();
if (Platform.isIOS) {
  iniData.enableCallKit = true;
  iniData.enablePushKit = true; // enable only when your server sends VoIP pushes
}
await PjsipConnectFlutter.instance.initialize(iniData, logsModel);
```

**3. Send the PushKit token to your SIP server / push gateway** so it can
trigger a VoIP push when an INVITE arrives while the app is asleep:

```dart
final token = await PjsipConnectFlutter.instance.getPushKitToken();
// Deliver `token` to your server (e.g. in a REGISTER header or via your API).
```

**4. Handle the incoming push.** The plugin reports the call to CallKit
immediately (an iOS requirement), then raises `onIncomingPush`. Override it in
your `CallsModel` subclass to parse your gateway's payload and fill in the
caller details shown on the CallKit screen:

```dart
class AppCallsModel extends CallsModel {
  @override
  void onIncomingPush(String callkitUuid, Map<String, dynamic> payload) {
    PjsipConnectFlutter.instance.updateCallKitCallDetails(
        callkitUuid, null, payload['callerName'], payload['caller'], false);
  }
}
```

When the SIP INVITE arrives moments later, the plugin matches it to the same
CallKit window automatically. Optional `InitData` tweaks:
`enableCallKitRecents`, `enableCallKitMute`, `enableCallKitReportCallAsVideo`.

## Android: FCM push notifications

On Android, use Firebase Cloud Messaging to wake the app so it can re-register
and receive the INVITE. Add `firebase_core` and `firebase_messaging` to your
app, then register a background handler **before** `runApp`:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: gFCMOptions);
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  // ... create models, runApp(...)
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Runs in a background isolate — the app/Activity may be fully stopped.
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: gFCMOptions);

  // Re-initialize the engine and restore saved accounts so the
  // incoming INVITE (sent by your server after the push) can be received.
  await PjsipConnectFlutter.instance.initialize(InitData());

  final prefs = await SharedPreferences.getInstance();
  final accJson = prefs.getString('accounts') ?? '';
  if (accJson.isNotEmpty) {
    final accsModel = AccountsModel();
    await accsModel.loadFromJson(accJson);
    accsModel.refreshRegistration();
  }
}
```

Your SIP server (or push gateway) sends a **data-only** FCM message when a
call arrives for an offline device; the handler above brings the SIP stack
back up so the INVITE reaches the app. See the full working version
(commented out, with Firebase options) in
[`example/lib/main.dart`](example/lib/main.dart).

To keep calls alive with the app backgrounded, also enable the plugin's
foreground service with an ongoing-call notification:

```dart
await devicesModel.setForegroundMode(true);
```

## License

This plugin bundles PJSIP, which is licensed under the
**GNU General Public License v2** (or a commercial license available from
Teluu). Consequently this package is distributed under **GPL-2.0** — see
[LICENSE](LICENSE).

In practice this means apps that distribute this plugin must either comply
with the GPL (make their source available under a GPL-compatible license) or
obtain a [commercial PJSIP license](https://www.pjsip.org/licensing.htm).

## Contact

Maintained by Sreerag K M — reach out on
[LinkedIn](https://www.linkedin.com/in/sreerag-k-m-310a05215/).
