import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

logger(String message) {
  Logger.log('', message);
}

class Logger {
  static Map<String, Function(Log)> logListeners = {};

  static log(String tag, String message) {
    if (kDebugMode) {
      print('logger: $message');
    }
    var log = Log(DateTime.now(), message, tag);
    for (var listener in logListeners.values) {
      listener(log);
    }
    Sentry.addBreadcrumb(Breadcrumb(message: message, category: 'logger'));
  }

  static setLogListener(String name, Function(Log) listener) {
    logListeners[name] = listener;
  }
}

class Log {
  DateTime time;
  String message;
  String tag;

  Log(this.time, this.message, this.tag);
}
