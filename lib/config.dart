import 'package:flutter/foundation.dart';

import 'env.dart';

class Config {
  static final mixpanelProjectToken = _getEnv('__APP__MIXPANEL_PROJECT_TOKEN');
  static final sentryDsn = _getEnv('__APP__SENTRY_DSN');
  static final firebaseApiKey = _getEnv('__APP__FIREBASE_API_KEY');
  static final firebaseProjectId = _getEnv('__APP__FIREBASE_PROJECT_ID');

  static const sendErrorAndAnalyticsLogs = !kDebugMode;

  static String _getEnv(String key) {
    var value = environment[key];
    if (value == null) throw Exception('Missing env value for $key');
    return value;
  }
}
