import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firedart/auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../helpers.dart';
import '../model/value_store.dart';
import '../reporting/error_logger.dart';
import '../reporting/logger.dart';

enum AnalyticsEvent {
  appLaunched,
  fileSelectionStarted,
  payloadSelected,
  receiverSelected,
  receiverDeleted,
  pairingDialogShown,
  pairingStarted,
  pairingCompleted,
  sendingStarted,
  sendingCompleted,
  receivingStarted,
  receivingCompleted,
  fileActionTaken,
  errorLogged,
}

extension AnalyticsEventName on AnalyticsEvent {
  void log([Map<String, dynamic>? props]) {
    Analytics.logEvent(this, props);
  }

  String get name {
    switch (this) {
      case AnalyticsEvent.appLaunched:
        return 'App Launched';
      case AnalyticsEvent.fileSelectionStarted:
        return 'File Selection Started';
      case AnalyticsEvent.payloadSelected:
        return 'File Selected';
      case AnalyticsEvent.receiverSelected:
        return 'Receiver Selected';
      case AnalyticsEvent.receiverDeleted:
        return 'Receiver Deleted';
      case AnalyticsEvent.pairingDialogShown:
        return 'Pairing Dialog Shown';
      case AnalyticsEvent.pairingStarted:
        return 'Pairing Started';
      case AnalyticsEvent.pairingCompleted:
        return 'Pairing Completed';
      case AnalyticsEvent.sendingStarted:
        return 'Sending Started';
      case AnalyticsEvent.sendingCompleted:
        return 'Sending Completed';
      case AnalyticsEvent.receivingStarted:
        return 'Receiving Started';
      case AnalyticsEvent.receivingCompleted:
        return 'Receiving Completed';
      case AnalyticsEvent.fileActionTaken:
        return 'File Action Taken';
      case AnalyticsEvent.errorLogged:
        return 'Error Logged';
    }
  }
}

class Analytics {
  static final _manager = AnalyticsManager();

  static void logEvent(AnalyticsEvent event, [Map<String, dynamic>? props]) {
    _manager
        .logEvent(event.name, props ?? <String, String>{})
        .catchError((Object error, StackTrace stack) {
      print('ANALYTICS: Error when posting event ${event.name}');
      ErrorLogger.logError(
          AnalyticsLogError('analyticsEventError', error, stack));
    });
  }

  static Future<void> updateProfile(String deviceId) async {
    var prefs = await SharedPreferences.getInstance();
    ValueStore(prefs).updateStartValues();

    var analyticsManager = AnalyticsManager();
    var userProps = await analyticsManager.getUserProperties();

    _manager
        .updateMixpanelProfile(FirebaseAuth.instance.userId, userProps)
        .catchError((Object error, StackTrace stack) {
      ErrorLogger.logError(
          AnalyticsLogError('analyticsProfileError', error, stack));
    });
  }
}

class AnalyticsManager {
  static var loggedEvents = <dynamic, dynamic>{};

  Future<int> getBuildNumber() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();

    var version = packageInfo.version;

    if (packageInfo.version.isEmpty) {
      ErrorLogger.logSimpleError('emptyAppVersion');
      version = '0.0.0';
    }
    var rawBuildNumber = packageInfo.buildNumber;

    // There seem to be no concept of buildNumber on windows. Flutter
    // might support this somehow in the future however.
    // Related issue: https://github.com/fluttercommunity/plus_plugins/issues/343
    if (rawBuildNumber.isEmpty) {
      var parts = version.split('.');
      rawBuildNumber = parts.tryGet(2) ?? '';
    }
    int buildNumber;
    try {
      buildNumber = int.parse(rawBuildNumber);
    } catch (error) {
      ErrorLogger.logSimpleError('invalidBuildNumber');
      buildNumber = -1;
    }

    return buildNumber;
  }

  Future<Map<String, dynamic>> getUserProperties() async {
    // ignore: deprecated_member_use
    final flutterWindow = window;

    final deviceInfoPlugin = DeviceInfoPlugin();
    final deviceInfo = await deviceInfoPlugin.deviceInfo;

    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    var buildNumber = await getBuildNumber();

    var prefs = await SharedPreferences.getInstance();
    int appOpens = prefs.getInt('appOpenCount') ?? 0;
    appOpens++;
    prefs.setInt('appOpenCount', appOpens);

    var info = deviceInfo.data;
    String model = info['utsname']?['machine'] as String? ??
        info['model'] as String? ??
        '';
    String deviceName =
        info['name'] as String? ?? info['computerName'] as String? ?? '';
    String brand = Platform.isMacOS || Platform.isIOS
        ? 'Apple'
        : info['manufacturer'] as String? ?? '';

    var screenSize = flutterWindow.physicalSize;
    var timezoneOffset = DateTime.now().timeZoneOffset.inSeconds;

    var firstSeenAt =
        prefs.getString('firstSeenAt') ?? DateTime.now().toIso8601String();
    prefs.setString('firstSeenAt', firstSeenAt);

    var deviceId = prefs.getString('deviceId') ?? '';

    var userProps = {
      'App Open Count': appOpens,
      'Environment': kDebugMode ? 'Development' : 'Production',
      'Device Country Code': flutterWindow.locale.countryCode,
      'Device Language Code': flutterWindow.locale.languageCode,
      'Timezone Offset': timezoneOffset,
      'First Seen At': firstSeenAt,
      '\$model': model,
      '\$manufacturer': brand,
      '\$device': deviceName,
      '\$screen_height': screenSize.height / flutterWindow.devicePixelRatio,
      '\$screen_width': screenSize.width / flutterWindow.devicePixelRatio,
      '\$device_id': deviceId,
      '\$app_version_string': packageInfo.version,
      '\$app_build_number': buildNumber,
      '\$os': Platform.operatingSystem,
      '\$user_id': FirebaseAuth.instance.userId,
      'OS Version': Platform.operatingSystemVersion,
    };
    return userProps;
  }

  Future<void> updateMixpanelProfile(
      String userId, Map<String, dynamic> props) async {
    var mixPanelToken = Config.mixpanelProjectToken;
    if (mixPanelToken == null) {
      print('ANALYTICS: Would have updated profile $userId');
      return;
    }

    props = _unifyProps(props, '_profile_');

    var body = {
      '\$token': mixPanelToken,
      '\$distinct_id': FirebaseAuth.instance.userId,
      '\$set': props,
    };

    var current = jsonEncode([body]);
    var headers = {'Content-Type': 'application/json'};
    var uri = Uri.parse('https://api.mixpanel.com/engage#profile-set');

    if (Config.sendErrorAndAnalyticsLogs) {
      var result = await http.post(uri, headers: headers, body: current);
      if (result.body != '1') {
        throw Exception('Update profile error: ${result.body}');
      }
      logger('ANALYTICS: Updated profile');
    } else {
      logger('ANALYTICS: Skipped updating analytics profile');
    }
  }

  Future<void> logEvent(String eventName, Map<String, dynamic> props) async {
    var mixPanelToken = Config.mixpanelProjectToken;
    if (mixPanelToken == null) {
      print('ANALYTICS: Would have logged $eventName');
      return;
    }

    var userProps = await getUserProperties();
    props = _unifyProps(<String, dynamic>{...props, ...userProps}, eventName);

    var eventProps = <String, dynamic>{
      'time': DateTime.now().millisecondsSinceEpoch,
      'token': mixPanelToken,
      'distinct_id': FirebaseAuth.instance.userId,
      ...props,
    };

    var body = {
      'airdash_event_id': generateId(10),
      'event': eventName,
      'properties': eventProps,
    };
    queueRequest(body);

    var crumb =
        Breadcrumb(message: eventName, category: 'analytics', data: props);
    Sentry.addBreadcrumb(crumb);
  }

  Future<void> upload() async {
    var prefs = await SharedPreferences.getInstance();

    var rawRequests = prefs.getString('pendingMixpanelRequests');
    var requests = List<Map<String, dynamic>>.from(
        jsonDecode(rawRequests ?? '[]') as List);

    while (requests.isNotEmpty) {
      var request = requests.removeLast();
      var current = jsonEncode([request]);
      var headers = {'Content-Type': 'application/json'};

      if (AnalyticsManager.loggedEvents[request['airdash_event_id']] != null) {
        print('ANALYTICS: Skipped already logged event');
        continue;
      }
      AnalyticsManager.loggedEvents[request['airdash_event_id']] = true;

      if (Config.sendErrorAndAnalyticsLogs) {
        var mixpanelApiUrl =
            Uri.parse('https://api.mixpanel.com/track?verbose=1&ip=1');
        logger('ANALYTICS: Will post event "${request['event']}"');
        var response =
            await http.post(mixpanelApiUrl, headers: headers, body: current);

        var body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['status'] != 1) {
          ErrorLogger.logError(LogError(
              'analyticsEventNotAccepted', null, null, <String, dynamic>{
            'body': response.body,
            'status': response.statusCode,
            'reason': response.reasonPhrase,
            'event': current,
          }));
        }
      }

      logger(
          'ANALYTICS: Logged event "${request['event']}" (sent: ${Config.sendErrorAndAnalyticsLogs})');
    }

    var json = jsonEncode(requests);
    prefs.setString('pendingMixpanelRequests', json);
  }

  void queueRequest(Map<String, dynamic> body) async {
    var prefs = await SharedPreferences.getInstance();
    var rawRequests = prefs.getString('pendingMixpanelRequests');
    var requests = jsonDecode(rawRequests ?? '[]') as List;
    requests.add(body);

    if (requests.length > 100) {
      var prefs = await SharedPreferences.getInstance();
      var hasPosted = prefs.getBool('tooManyAnalyticsEventsPosted') ?? false;
      if (hasPosted) {
        ErrorLogger.logSimpleError('tooManyAnalyticsEvents', <String, dynamic>{
          'count': requests.length,
        });
        requests.removeAt(0);
        await prefs.setBool('tooManyAnalyticsEventsPosted', true);
      }
    }

    var json = jsonEncode(requests);
    prefs.setString('pendingMixpanelRequests', json);

    await upload();
  }

  Map<String, dynamic> _unifyProps(
      Map<String, dynamic> props, String eventName) {
    for (var key in props.keys) {
      dynamic value = props[key] ?? '(null)';
      if (value is DateTime) {
        props[key] = value.toIso8601String();
      } else if (value is! String &&
          value is! num &&
          value is! bool &&
          value is! Map &&
          value is! List) {
        ErrorLogger.logSimpleError('invalidEventPropertyType', <String, String>{
          'type': value.runtimeType.toString(),
          'key': key,
          'eventName': eventName,
        });
        props[key] = value.toString();
      }
    }
    return props;
  }
}
