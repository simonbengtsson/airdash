import 'package:flutter/foundation.dart';

import 'env.dart';

class Config {
  static final String? customPairingFunctionUrl =
      _getEnv('__APP__PAIRING_FUNCTION_URL');
  static final String firebaseApiKey = _getEnv('__APP__FIREBASE_API_KEY')!;
  static final String firebaseProjectId =
      _getEnv('__APP__FIREBASE_PROJECT_ID')!;
  static final String? mixpanelProjectToken =
      _getEnv('__APP__MIXPANEL_PROJECT_TOKEN');
  static final String sentryDsn =
      _getEnv('__APP__SENTRY_DSN') ?? 'https://foo@bar.ingest.sentry.io/foo';

  static const sendErrorAndAnalyticsLogs = !kDebugMode;

  static String getPairingFunctionUrl() {
    var customUrl = customPairingFunctionUrl;
    if (customUrl != null) {
      return customUrl;
    }
    return 'https://us-central1-$firebaseProjectId.cloudfunctions.net/pairing';
  }

  static String? _getEnv(String key) {
    var value = environment[key];
    return value;
  }
}
