// ignore_for_file: public_member_api_docs

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The plugin's single MethodChannel (must match the native side).
const MethodChannel kPjsipConnectChannel = MethodChannel('sip_connect_flutter');

/// Fakes the native side of the `sipconnect_voip_sdk` channel.
///
/// - Records every Dart→native [MethodCall] in [calls].
/// - Answers with the canned values in [responses] (override per-test or set
///   [onCall] for dynamic behavior / throwing PlatformException).
/// - [emitEvent] simulates a native→Dart event (reverse method call), which is
///   how the real plugin delivers `On*` events.
class MockPjsipConnectNative {
  MockPjsipConnectNative() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kPjsipConnectChannel, _handler);
  }

  final List<MethodCall> calls = [];

  /// Canned response per method name; null (absent) means a void reply.
  final Map<String, Object?> responses = {
    'Module_Version': '5.0.0-test',
    'Module_VersionCode': 500,
    'Module_HomeFolder': '/tmp/sipconnect-test/',
    'Account_Add': 5,
    'Account_GenInstId': 'test-inst-id',
    'Call_Invite': 42,
    'Call_GetHoldState': 0,
    'Call_GetSipHeader': '',
    'Call_GetStats': '{}',
    'Call_PlayTone': 3,
    'Call_PlayFile': 4,
    'Message_Send': 11,
    'Subscription_Add': 21,
    'Video_RendererCreate': 7,
    'Dvc_GetPlayoutDevices': 2,
    'Dvc_GetRecordingDevices': 0,
    'Dvc_GetVideoDevices': 0,
    'Dvc_GetPlayoutDevice': {'name': 'Speaker', 'guid': '0'},
  };

  /// Optional dynamic handler; may throw [PlatformException]. When it returns
  /// non-null, that value is used instead of [responses].
  Object? Function(MethodCall call)? onCall;

  Future<Object?> _handler(MethodCall call) async {
    calls.add(call);
    final Object? custom = onCall?.call(call);
    return custom ?? responses[call.method];
  }

  /// All recorded calls with the given method name.
  Iterable<MethodCall> named(String method) =>
      calls.where((c) => c.method == method);

  /// The single recorded call with the given name (fails if 0 or >1).
  MethodCall single(String method) => named(method).single;

  void reset() => calls.clear();

  /// Unregisters the mock handler.
  void dispose() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(kPjsipConnectChannel, null);
  }

  /// Simulates the native side invoking a Dart handler (an `On*` event).
  Future<void> emitEvent(String method, Object? arguments) async {
    final ByteData data = const StandardMethodCodec().encodeMethodCall(
      MethodCall(method, arguments),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          kPjsipConnectChannel.name,
          data,
          (ByteData? reply) {},
        );
  }
}
