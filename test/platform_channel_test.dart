// Channel round-trip tests: Dart->native method encoding and native->Dart
// event dispatch, using a mocked platform channel (no native code involved).

import 'package:flutter_test/flutter_test.dart';
import 'package:pjsip_connect_flutter/pjsip_connect_flutter.dart';

import 'helpers/mock_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPjsipConnectNative native;
  final sdk = PjsipConnectFlutter();

  setUp(() async {
    native = MockPjsipConnectNative();
    // initialize() registers the events handler and calls
    // Module_Initialize + Module_Version on the (mocked) native side.
    await sdk.initialize(InitData());
    native.reset();
  });

  tearDown(() {
    native.dispose();
    sdk.accListener = null;
    sdk.callListener = null;
    sdk.netListener = null;
    sdk.messagesListener = null;
    sdk.vuMeterListener = null;
  });

  group('Dart -> native encoding', () {
    test('initialize sends Module_Initialize with InitData json', () async {
      final ini = InitData()..logLevelFile = LogLevel.debug;
      await sdk.initialize(ini);

      final call = native.single('Module_Initialize');
      final args = call.arguments as Map;
      expect(args['logLevelFile'], LogLevel.debug.id);
      // No license key is sent unless explicitly set.
      expect(args.containsKey('license'), isFalse);
    });

    test('addAccount sends Account_Add and returns native id', () async {
      final acc = AccountModel(
          sipServer: 'sip.example.com', sipExtension: '100', sipPassword: 'pw');
      final accId = await sdk.addAccount(acc);

      expect(accId, 5);
      final args = native.single('Account_Add').arguments as Map;
      expect(args['sipServer'], 'sip.example.com');
      expect(args['sipExtension'], '100');
      expect(args['sipPassword'], 'pw');
    });

    test('registerAccount / unRegisterAccount / deleteAccount args', () async {
      await sdk.registerAccount(5, 300);
      await sdk.unRegisterAccount(5);
      await sdk.deleteAccount(5);

      expect(native.single('Account_Register').arguments,
          {'accId': 5, 'expireTime': 300});
      expect(native.single('Account_Unregister').arguments, {'accId': 5});
      expect(native.single('Account_Delete').arguments, {'accId': 5});
    });

    test('invite sends Call_Invite with destination json', () async {
      final dest = CallDestination('200', 5, false);
      final callId = await sdk.invite(dest);

      expect(callId, 42);
      final args = native.single('Call_Invite').arguments as Map;
      expect(args['extension'], '200');
      expect(args['accId'], 5);
      expect(args['withVideo'], false);
    });

    test('call control methods encode ids and flags', () async {
      await sdk.accept(42, true);
      await sdk.hold(42);
      await sdk.muteMic(42, true);
      await sdk.sendDtmf(42, '1#', 200, 50, PjsipConnectFlutter.kDtmfMethodRtp);
      await sdk.bye(42);
      await sdk.reject(7, 486);
      await sdk.transferBlind(42, '300');
      await sdk.transferAttended(42, 43);

      expect(native.single('Call_Accept').arguments,
          {'callId': 42, 'withVideo': true});
      expect(native.single('Call_Hold').arguments, {'callId': 42});
      expect(native.single('Call_MuteMic').arguments,
          {'callId': 42, 'mute': true});
      expect(native.single('Call_SendDtmf').arguments, {
        'callId': 42,
        'dtmfs': '1#',
        'durationMs': 200,
        'intertoneGapMs': 50,
        'method': PjsipConnectFlutter.kDtmfMethodRtp,
      });
      expect(native.single('Call_Bye').arguments, {'callId': 42});
      expect(native.single('Call_Reject').arguments,
          {'callId': 7, 'statusCode': 486});
      expect(native.single('Call_TransferBlind').arguments,
          {'callId': 42, 'toExt': '300'});
      expect(native.single('Call_TransferAttended').arguments,
          {'fromCallId': 42, 'toCallId': 43});
    });

    test('video renderer lifecycle methods', () async {
      final textureId = await sdk.videoRendererCreate();
      expect(textureId, 7);

      await sdk.videoRendererSetSourceCall(7, 42);
      await sdk.videoRendererDispose(7);

      expect(native.single('Video_RendererSetSrc').arguments,
          {'videoTextureId': 7, 'callId': 42});
      expect(native.single('Video_RendererDispose').arguments,
          {'videoTextureId': 7});
    });
  });

  group('native -> Dart event dispatch', () {
    test('OnAccountRegState reaches accListener with parsed enum', () async {
      final received = <(int, RegState, String)>[];
      sdk.accListener = AccStateListener(
          regStateChanged: (accId, state, response) =>
              received.add((accId, state, response)));

      await native.emitEvent('OnAccountRegState',
          {'accId': 5, 'regState': PjsipConnectFlutter.kRegStateFailed, 'response': '403 Forbidden'});

      expect(received, [(5, RegState.failed, '403 Forbidden')]);
    });

    test('OnCallIncoming reaches callListener', () async {
      final received = <(int, int, bool, String, String)>[];
      sdk.callListener = CallStateListener(
          incoming: (callId, accId, withVideo, from, to) =>
              received.add((callId, accId, withVideo, from, to)));

      await native.emitEvent('OnCallIncoming', {
        'callId': 42,
        'accId': 5,
        'withVideo': false,
        'from': '"Alice" <sip:100@example.com>',
        'to': 'sip:200@example.com',
      });

      expect(received.length, 1);
      expect(received.first.$1, 42);
      expect(received.first.$4, contains('Alice'));
    });

    test('OnCallTerminated and OnNetworkState dispatch', () async {
      int? terminatedCallId;
      NetState? netState;
      sdk.callListener =
          CallStateListener(terminated: (callId, code) => terminatedCallId = callId);
      sdk.netListener = NetStateListener(
          networkStateChanged: (name, state) => netState = state);

      await native.emitEvent('OnCallTerminated', {'callId': 42, 'statusCode': 200});
      await native.emitEvent('OnNetworkState',
          {'name': 'wlan0', 'netState': PjsipConnectFlutter.kNetStateRestored});

      expect(terminatedCallId, 42);
      expect(netState, NetState.restored);
    });

    test('event with extra unknown keys still dispatches', () async {
      int? callId;
      sdk.callListener =
          CallStateListener(terminated: (id, code) => callId = id);

      await native.emitEvent('OnCallTerminated',
          {'callId': 42, 'statusCode': 200, 'someNewField': 'future-proof'});

      expect(callId, 42, reason: 'parsers must tolerate added fields');
    });

    test('event missing a required key is dropped silently', () async {
      int? callId;
      sdk.callListener =
          CallStateListener(terminated: (id, code) => callId = id);

      await native.emitEvent('OnCallTerminated', {'callId': 42}); // no statusCode

      expect(callId, isNull,
          reason: 'current contract: incomplete events are ignored');
    });

    test('unknown event name and non-map payload are ignored', () async {
      // Must not throw.
      await native.emitEvent('OnSomethingNew', {'x': 1});
      await native.emitEvent('OnCallTerminated', 'not-a-map');
    });

    test('OnMessageIncoming and OnVuMeterLevel dispatch', () async {
      final messages = <(int, int, String, String)>[];
      final levels = <(int, int)>[];
      sdk.messagesListener = MessagesStateListener(
        incoming: (msgId, accId, from, body) => messages.add((msgId, accId, from, body)),
        sentState: (msgId, success, response) {},
      );
      sdk.vuMeterListener = VuMeterListener(vu: (mic, spk) => levels.add((mic, spk)));

      await native.emitEvent('OnMessageIncoming',
          {'msgId': 11, 'accId': 5, 'from': 'sip:100@x.com', 'body': 'hello'});
      await native.emitEvent('OnVuMeterLevel', {'mic': 3, 'spk': 7});

      expect(messages, [(11, 5, 'sip:100@x.com', 'hello')]);
      expect(levels, [(3, 7)]);
    });
  });
}
