# iOS Call Setup Guide

How to set up voice calls on iOS with `pjsip_connect_flutter` — from a basic
foreground-only app to full background/killed-app incoming calls with
CallKit + PushKit.

## How iOS calling works (overview)

```
Foreground app:
  SIP server ──INVITE over TLS/TCP──▶ engine ──▶ onIncomingSip ──▶ your UI

Background / killed app:
  SIP server ──VoIP push via APNs──▶ iOS wakes app
      ├─▶ plugin reports call to CallKit immediately (native ring UI)
      ├─▶ engine restarts transports + re-registers (automatic)
      ├─▶ onIncomingPush fired to Dart (update caller name on CallKit screen)
      └─▶ real SIP INVITE arrives ──▶ you match it to the CallKit call
```

While the app is in the foreground the engine keeps its own connection to
your SIP server, so **calls work with no push setup at all**. PushKit is only
needed to receive calls while the app is backgrounded or killed — iOS freezes
the app and closes its sockets, so the server needs a way to wake it.

---

## Step 1 — Xcode project configuration

In your Runner target:

1. **Signing & Capabilities** → add:
   - *Push Notifications*
   - *Background Modes* → check **Voice over IP** (and *Audio* if you play
     ringtones yourself)
2. **Info.plist** → add the microphone permission (calls will have no audio
   without it):

```xml
<key>NSMicrophoneUsageDescription</key>
<string>Microphone access is required for voice calls.</string>
```

## Step 2 — Initialize the engine with CallKit (and PushKit)

Initialize once at app startup, before adding accounts
(see [`example/lib/main.dart`](../example/lib/main.dart)):

```dart
final iniData = InitData();
if (Platform.isIOS) {
  iniData.enableCallKit = true;
  iniData.enablePushKit = true; // only when your server sends VoIP pushes
  iniData.unregOnDestroy = false;
}
await PjsipConnectFlutter.instance.initialize(iniData, logsModel);
```

- `enableCallKit` gives you the native iOS call screen (lock-screen answer,
  in-call status bar, mute from CallKit) and correct audio-session handling.
- `enablePushKit` creates the `PKPushRegistry` and makes the plugin report
  every VoIP push to CallKit (an iOS requirement).

Then register your account as usual with `AccountsModel.addAccount(...)`.
At this point **outgoing calls and foreground incoming calls already work**.

## Step 3 — VoIP push certificate (server side)

> 🛠 Server-side details (APNs request format, push payload, `X-PushHint`
> header, retry timing) are covered in the
> [iOS Backend Configuration Guide](ios_backend_setup.md).

1. In the Apple Developer portal create a **VoIP Services Certificate** for
   your bundle id and install it on your SIP server / push gateway.
2. The server must send a **VoIP push through APNs** (not a regular alert
   push) whenever an INVITE targets a device whose registration is
   unreachable — and it must send it for *every* incoming call if the app has
   PushKit enabled, because iOS expects each VoIP push to become a CallKit
   call.

## Step 4 — Deliver the PushKit token to your server

```dart
final token = await PjsipConnectFlutter.instance.getPushKitToken();
// Send `token` to your SIP server / push gateway — e.g. in a REGISTER
// header or through your backend API.
```

The token can change; re-send it after `initialize()` on every app start.

## Step 5 — Handle the push and match it to the SIP call

When a VoIP push arrives the plugin has *already* shown the CallKit ring
screen before Dart hears about it. Your job in Dart is to:

1. Put the real caller name/number on the CallKit screen.
2. Match the push to the SIP INVITE that arrives moments later (either order
   is possible), so answering/declining controls the right SIP call.

The recommended pattern is the `CallMatcher` implementation in
[`example/lib/calls_model_app.dart`](../example/lib/calls_model_app.dart) —
copy that class into your app. The essence:

```dart
class AppCallsModel extends CallsModel {
  @override
  void onIncomingPush(String callkitUuid, Map<String, dynamic> payload) {
    final aps = Map<String, dynamic>.from(payload['aps']);
    // 'pushHint' is a value your server puts in BOTH the push payload and
    // the INVITE (e.g. an X-PushHint header) so the two can be matched.
    final pushHint = aps['pushHint'];

    // Show caller details on the already-ringing CallKit screen.
    PjsipConnectFlutter().updateCallKitCallDetails(
        callkitUuid, /*sipCallId:*/ null, aps['callerName'], aps['callerNumber'], false);
    // ... store (callkitUuid, pushHint) and start a cleanup timer — see example.
  }

  @override
  void onIncomingSip(int callId, int accId, bool withVideo,
      String hdrFrom, String hdrTo) async {
    super.onIncomingSip(callId, accId, withVideo, hdrFrom, hdrTo);
    // Read the hint from the INVITE and link the SIP call to the CallKit call:
    final pushHint = await PjsipConnectFlutter().getSipHeader(callId, 'X-PushHint');
    // ... find the stored callkitUuid for this hint, then:
    // PjsipConnectFlutter().updateCallKitCallDetails(callkitUuid, callId, null, null, null);
  }
}
```

Push payload your server should send (matching the example app):

```json
{
  "aps": {
    "pushHint":     "unique-call-id-put-also-in-X-PushHint-header",
    "callerName":   "Alice",
    "callerNumber": "101",
    "withVideo":    false
  }
}
```

What the plugin handles for you automatically:

- Reporting the push to CallKit immediately (avoids the iOS 13+ kill penalty).
- Restarting SIP transports and refreshing registrations when the push wakes
  a suspended app, so the INVITE can actually reach the device.
- If the user answers or declines **before** the INVITE has arrived, the
  action is queued and executed as soon as you match the call with
  `updateCallKitCallDetails(uuid, sipCallId, ...)`.
- Audio session activation/deactivation through CallKit.

What your app must handle:

- The matching above (`updateCallKitCallDetails` with the SIP call id).
- Ending the CallKit call if no INVITE ever arrives — see the 15-second
  cleanup timer (`endCallKitCall`) in the example.

## Step 6 — Test checklist (physical device required)

1. **Foreground:** register, call the extension → your in-app UI rings,
   two-way audio after answer.
2. **Outgoing + CallKit:** place a call → green status bar / Dynamic Island
   call indicator appears; mute from CallKit mutes SIP audio.
3. **Background:** home-screen the app, call → CallKit full-screen ring,
   answer connects with audio.
4. **Killed:** swipe the app away, call → device rings via CallKit, answering
   launches the app and connects the call.

Steps 3–4 only work when your server actually sends the VoIP push.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| No ring when app killed | Server didn't send a VoIP push (check APNs response), or the VoIP certificate doesn't match the bundle id |
| CallKit rings but call never connects | INVITE didn't reach the device — check that the account re-registered after the push (device logs show `handleIncomingPush: restarting transports`) |
| Ring shows "callerName" placeholder | `onIncomingPush` isn't overridden, or the push payload keys don't match what you parse |
| Answer does nothing | The SIP call was never matched — `updateCallKitCallDetails(uuid, sipCallId, ...)` not called when the INVITE arrived |
| No audio after answer | Missing `NSMicrophoneUsageDescription`, or testing on the simulator (CallKit/audio need a real device) |
| Token is null | `enablePushKit`/`enableCallKit` not set in `InitData`, or running on the simulator |
