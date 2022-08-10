import 'package:flutter/foundation.dart';
import 'package:grpc/grpc.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../helpers.dart';
import 'logger.dart';

class ErrorLogger {
  static void addInfo(String message, Map<String, dynamic>? data) {
    Sentry.addBreadcrumb(Breadcrumb(
        message: message, category: 'info', data: data ?? <String, String>{}));
  }

  static void logError(LogError error) {
    _logError(error, null).catchError(_onError);
  }

  static void logStackError(String type, dynamic error, StackTrace stack,
      [int? errorCount]) {
    _logError(LogError(type, error, stack, null), errorCount)
        .catchError(_onError);
  }

  static void logSimpleError(String type,
      [Map<String, dynamic>? data, int? errorCount]) {
    _logError(LogError(type, null, null, data), errorCount)
        .catchError(_onError);
  }

  static void _onError(dynamic error) {
    print(
        'SEVERE! Caught $error error when logging sentry error, but not posted');
  }

  static Map<String, int> loggedCount = {};

  static Future _logError(LogError error, int? errorCount) async {
    print('LOG_ERROR: ${error.type}');
    if (errorCount != null) {
      var current = loggedCount[error.type] ?? 0;
      // Ignore all these errors for now
      if (current >= errorCount || true) {
        logger(
            'LOG: Error count reached, ignoring error of type ${error.type}');
        return;
      }
      //loggedCount[error.type] = current + 1;
    }
    if (error.error != null) {
      var details =
          FlutterErrorDetails(exception: error.error!, stack: error.stack);
      FlutterError.presentError(details);
    }
    Sentry.captureException(error, stackTrace: error.stack, withScope: (scope) {
      scope.setTag('action', 'logged');
      scope.setTag('type', error.type);
      for (var key in (error.context ?? <String, String>{}).keys) {
        scope.setExtra(key, error.context?[key] ?? '(null)');
      }
      var actual = error.error;
      if (actual != null) {
        if (actual is LogError) {
        } else {
          var details =
              FlutterErrorDetails(exception: actual, stack: error.stack);
          FlutterError.presentError(details);
        }

        scope.setExtra('wrappedException', error.error?.toString() ?? 'none');
        scope.setExtra('wrappedExceptionType',
            error.error?.runtimeType.toString() ?? 'none');
        scope.setExtra('isGrpc', actual is GrpcError);
        if (actual is GrpcError) {
          scope.setExtra('code', actual.code);
          scope.setExtra('message', actual.message ?? '');
          scope.setExtra('codeName', actual.codeName);
        } else if (actual is LogError) {
          scope.setExtra('subType', actual.type);
          scope.setExtra('subError', actual.error?.toString() ?? '');
          for (var key in (actual.context ?? <String, String>{}).keys) {
            scope.setExtra('subContext_$key', actual.context![key]);
          }
        }
      }
    });
  }
}
