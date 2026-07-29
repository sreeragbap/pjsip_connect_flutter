// Model-layer tests: ChangeNotifier state transitions and JSON persistence,
// driven through the mocked platform channel.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pjsip_connect_flutter/pjsip_connect_flutter.dart';

import 'helpers/mock_native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockPjsipConnectNative native;

  setUp(() {
    native = MockPjsipConnectNative();
  });

  tearDown(() {
    native.dispose();
    PjsipConnectFlutter().accListener = null;
    PjsipConnectFlutter().callListener = null;
  });

  group('AccountModel JSON', () {
    test('toJson/fromJson round-trip preserves fields', () {
      final acc =
          AccountModel(
              sipServer: 'sip.example.com',
              sipExtension: '100',
              sipPassword: 'secret',
              expireTime: 300,
            )
            ..port = 5566
            ..transport = SipTransport.tls
            ..displName = 'Alice';

      final restored = AccountModel.fromJson(acc.toJson());

      expect(restored.sipServer, 'sip.example.com');
      expect(restored.sipExtension, '100');
      expect(restored.sipPassword, 'secret');
      expect(restored.expireTime, 300);
      expect(restored.port, 5566);
      expect(restored.transport, SipTransport.tls);
      expect(restored.displName, 'Alice');
      expect(restored.uri, '100@sip.example.com');
    });
  });

  group('AccountsModel', () {
    test('addAccount stores account with native id and notifies', () async {
      final model = AccountsModel();
      var notified = 0;
      model.addListener(() => notified++);

      final acc = AccountModel(
        sipServer: 'sip.example.com',
        sipExtension: '100',
        sipPassword: 'pw',
      );
      await model.addAccount(acc);

      expect(model.length, 1);
      expect(model[0].myAccId, 5, reason: 'id assigned by (mock) native side');
      expect(model[0].regState, RegState.inProgress);
      expect(model.selAccountId, 5, reason: 'first account becomes selected');
      expect(notified, greaterThan(0));
      // Local port is auto-generated when unset.
      expect(model[0].port, isNot(0));
    });

    test('duplicate account error adopts the existing native id', () async {
      final model = AccountsModel();
      native.onCall = (call) {
        if (call.method == 'Account_Add') {
          throw PlatformException(
            code: PjsipConnectFlutter.eDuplicateAccount.toString(),
            message: 'Duplicate account',
            details: 77,
          ); // id of the already-registered account
        }
        return null;
      };

      final acc = AccountModel(
        sipServer: 'sip.example.com',
        sipExtension: '100',
        sipPassword: 'pw',
      );
      await model.addAccount(acc);

      expect(model.length, 1);
      expect(
        model[0].myAccId,
        77,
        reason: 'service-restart reconciliation must adopt the existing id',
      );
    });

    test('other PlatformException surfaces as Future.error', () async {
      final model = AccountsModel();
      native.onCall = (call) {
        if (call.method == 'Account_Add') {
          throw PlatformException(code: '-1', message: 'boom');
        }
        return null;
      };

      expect(
        model.addAccount(AccountModel(sipServer: 's', sipExtension: 'e')),
        throwsA('boom'),
      );
    });

    test('onRegStateChanged updates matching account and notifies', () async {
      final model = AccountsModel();
      await model.addAccount(
        AccountModel(
          sipServer: 'sip.example.com',
          sipExtension: '100',
          sipPassword: 'pw',
        ),
      );
      var notified = 0;
      model.addListener(() => notified++);

      model.onRegStateChanged(5, RegState.success, '200 OK');

      expect(model[0].regState, RegState.success);
      expect(model[0].regText, '200 OK');
      expect(notified, 1);
    });
  });

  group('CallsModel', () {
    late AccountsModel accounts;
    late CallsModel calls;

    setUp(() async {
      accounts = AccountsModel();
      await accounts.addAccount(
        AccountModel(
          sipServer: 'sip.example.com',
          sipExtension: '100',
          sipPassword: 'pw',
        ),
      );
      calls = CallsModel(accounts);
    });

    test('onIncomingSip adds a ringing call and switches to it', () {
      var newCallCallbackFired = false;
      calls.onNewIncomingCall = () => newCallCallbackFired = true;

      calls.onIncomingSip(
        42,
        5,
        false,
        '"Bob" <sip:200@peer.com>',
        'sip:100@sip.example.com',
      );

      expect(calls.length, 1);
      expect(calls[0].myCallId, 42);
      expect(calls[0].isIncoming, isTrue);
      expect(calls[0].remoteExt, '200');
      expect(calls[0].displName, 'Bob');
      expect(calls[0].accUri, '100@sip.example.com');
      expect(calls.switchedCallId, 42);
      expect(newCallCallbackFired, isTrue);
    });

    test('duplicate onIncomingSip with same callId is ignored', () {
      calls.onIncomingSip(42, 5, false, 'sip:200@peer.com', 'sip:100@x.com');
      calls.onIncomingSip(42, 5, false, 'sip:200@peer.com', 'sip:100@x.com');
      expect(calls.length, 1);
    });

    test('invite adds outgoing call with id from native', () async {
      await calls.invite(CallDestination('200', 5, false));

      expect(calls.length, 1);
      expect(calls[0].myCallId, 42, reason: 'mock Call_Invite returns 42');
      expect(calls[0].isIncoming, isFalse);
    });

    test('onTerminated removes the call', () async {
      calls.onIncomingSip(42, 5, false, 'sip:200@peer.com', 'sip:100@x.com');
      expect(calls.length, 1);

      calls.onTerminated(42, 200);
      // onTerminated awaits Call_GetSipHeader before removing.
      await pumpEventQueue();

      expect(calls.length, 0);
    });
  });

  group('CdrsModel persistence', () {
    test('store/load JSON round-trip', () async {
      final accounts = AccountsModel();
      await accounts.addAccount(
        AccountModel(
          sipServer: 'sip.example.com',
          sipExtension: '100',
          sipPassword: 'pw',
        ),
      );
      final cdrs = CdrsModel();
      final calls = CallsModel(accounts, null, cdrs);

      calls.onIncomingSip(
        42,
        5,
        false,
        '"Bob" <sip:200@peer.com>',
        'sip:100@x.com',
      );
      calls.onTerminated(42, 486);
      await pumpEventQueue();
      expect(cdrs.length, 1);

      final json = cdrs.storeToJson();
      final restored = CdrsModel();
      expect(restored.loadFromJson(json), isTrue);
      expect(restored.length, 1);
      expect(restored[0].statusCode, 486);
      expect(restored[0].incoming, isTrue);
    });
  });
}
