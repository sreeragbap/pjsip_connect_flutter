# iOS Backend Configuration (VoIP Push)

What your SIP server / push gateway must do so iOS devices receive calls while
the app is backgrounded or killed. App-side setup is in the
[iOS Call Setup Guide](ios_call_setup.md).

## The flow

```
1. App sends you its PushKit token (REGISTER header or your API)
2. A call arrives for a sleeping device
3. Server sends a VoIP push via APNs  ──▶  iOS wakes the app, CallKit rings
4. Plugin re-registers automatically
5. Server sends the INVITE with an X-PushHint header
      (same value as "pushHint" in the push payload)
```

## 1. APNs credentials

Create a **VoIP Services Certificate** for the app's bundle id in the Apple
Developer portal (or use a `.p8` auth key). Note: Xcode/debug builds need the
**sandbox** APNs host, TestFlight/App Store builds the **production** host.

## 2. Store the push token

The app gets its token from `getPushKitToken()` and sends it to you (e.g. in a
REGISTER header). Store it per device; it can change, so always overwrite with
the latest value.

## 3. Send the push — for every call, only for calls

- Send a VoIP push for **every** incoming call to a push-enabled device, even
  if its registration looks fresh (iOS closes the app's sockets anyway).
- **Never** send a VoIP push for anything that isn't a call — iOS 13+ requires
  each VoIP push to become a CallKit call, or the app gets penalized.

## 4. The APNs request

HTTP/2 POST to `https://api.push.apple.com/3/device/{push-token}` with:

```
apns-topic: <bundle-id>.voip
apns-push-type: voip
apns-priority: 10
apns-expiration: 0
```

Payload (the exact keys the app parses):

```json
{
  "aps": {
    "pushHint":     "unique-id-for-this-call",
    "callerName":   "Alice",
    "callerNumber": "101",
    "withVideo":    false
  }
}
```

`pushHint` correlates the push with the INVITE — a UUID or the SIP Call-ID
works. `callerName` / `callerNumber` are shown on the CallKit ring screen.

## 5. Tag the INVITE

Add the same value to the INVITE as a custom header:

```
X-PushHint: unique-id-for-this-call
```

The app uses it to attach the INVITE to the already-ringing CallKit call.

## 6. Timing

After the push, the device needs a few seconds to wake and re-register — keep
retrying the INVITE for ~5 seconds. If no INVITE arrives, the app dismisses
the CallKit call after 15 seconds, so stay under that.

## Troubleshooting

| Problem | Fix |
|---|---|
| `BadDeviceToken` | Wrong environment — sandbox token sent to production (or vice versa) |
| `TopicDisallowed` | `apns-topic` must be `<bundle-id>.voip` |
| `410 Unregistered` | App uninstalled — delete the stored token |
| Rings but never connects | INVITE not retried after the push, or `X-PushHint` missing/mismatched |
