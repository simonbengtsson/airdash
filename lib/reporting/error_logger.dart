import 'package:firedart/firedart.dart';
import 'package:flutter/foundation.dart';
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

  static Future<void> _logError(LogError error, int? errorCount) async {
    print('LOG_ERROR: ${error.type} ${error.error}');
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
        scope.setContexts(key, error.context?[key] ?? '(null)');
      }
      var actual = error.error;
      if (actual != null) {
        if (actual is LogError) {
        } else {
          var details =
              FlutterErrorDetails(exception: actual, stack: error.stack);
          FlutterError.presentError(details);
        }

        scope.setContexts(
            'wrappedException', error.error?.toString() ?? 'none');
        scope.setContexts('wrappedExceptionType',
            error.error?.runtimeType.toString() ?? 'none');
        scope.setContexts('isGrpc', actual is GrpcError);
        if (actual is GrpcError) {
          scope.setContexts('code', actual.code);
          scope.setContexts('message', actual.message ?? '');
          scope.setContexts('codeName', actual.codeName);
        } else if (actual is LogError) {
          scope.setContexts('subType', actual.type);
          scope.setContexts('subError', actual.error?.toString() ?? '');
          for (var key in (actual.context ?? <String, String>{}).keys) {
            scope.setContexts('subContext_$key', actual.context![key]);
          }
        }
      }
    });
  }
}
