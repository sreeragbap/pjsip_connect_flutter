import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'pjsip_connect.dart';

/// LogLevel enum. Using as value of 'IniData.logLevelFile' 'IniData.logLevelIde'
enum LogLevel {
  ///Most detailed log level
  stack(PjsipConnectFlutter.kLogLevelStack, "Stack"),

  ///Detailed log level for regulr debugging
  debug(PjsipConnectFlutter.kLogLevelDebug, "Debug"),

  ///Default log level
  info(PjsipConnectFlutter.kLogLevelInfo, "Info"),

  ///Display warnings only
  warning(PjsipConnectFlutter.kLogLevelWarning, "Warning"),

  ///Display errors only
  error(PjsipConnectFlutter.kLogLevelError, "Error"),

  ///Don't display any logs
  none(PjsipConnectFlutter.kLogLevelNone, "None");

  const LogLevel(this.id, this.name);

  /// Value
  final int id;

  /// User friendly name of the selected option
  final String name;
}

/// Contains log string which can be displayed on UI. App can replace it with the own class or don't use
class LogsModel extends ChangeNotifier implements ILogsModel {
  String _logStr = "";
  final bool _uiLog;

  /// Cummulative log string
  String get logStr => _logStr;

  /// Constructor (set event handler)
  LogsModel(this._uiLog) {
    PjsipConnectFlutter().trialListener = TrialModeListener(
      notified: onTrialModeNotified,
    );
  }

  @override
  void print(String str) {
    debugPrint(str);

    if (_uiLog) {
      DateTime now = DateTime.now();
      _logStr += DateFormat('HH:mm:ss ').format(now);
      _logStr += str;
      _logStr += '\n';
      notifyListeners();
    }
  }

  /// Handle trial mode notification raised by library when license not set or wrong
  void onTrialModeNotified() {
    print("--- SDK is working in TRIAL mode ---");
  }
}
