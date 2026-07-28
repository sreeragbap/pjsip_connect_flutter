/// pjsip_connect_flutter — VoIP/SIP plugin for Android and iOS.
///
/// Provides voice/video calling, messaging, and BLF/presence subscriptions on
/// top of a PJSIP-based engine. Import this single file to access the full
/// public API (the low-level [PjsipConnectFlutter] facade, the `ChangeNotifier`
/// models, and the video widgets).
library pjsip_connect_flutter;

// `SaveChangesCallback` is declared identically in several model files; export it
// once (from accounts_model) and hide the duplicates to avoid an ambiguous export.
export 'pjsip_connect.dart';
export 'accounts_model.dart';
export 'calls_model.dart';
export 'messages_model.dart' hide SaveChangesCallback;
export 'subscriptions_model.dart' hide SaveChangesCallback;
export 'devices_model.dart';
export 'cdrs_model.dart' hide SaveChangesCallback;
export 'network_model.dart';
export 'logs_model.dart';
export 'video.dart';
