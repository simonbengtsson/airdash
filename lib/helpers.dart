import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:airdash/reporting/error_logger.dart';
import 'package:firedart/firedart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'model/device.dart';
import 'model/payload.dart';
import 'reporting/logger.dart';
import 'transfer/connector.dart';
import 'transfer/signaling.dart';

var communicatorChannel = const MethodChannel('io.flown.airdash/communicator');

// https://stackoverflow.com/a/62486490/827047
var random = Random();

String generateId(int len) {
  const chars =
      'AaBbCcDdEeFfGgHhIiJjKkLlMmNnOoPpQqRrSsTtUuVvWwXxYyZz1234567890';
  return List.generate(len, (index) => chars[random.nextInt(chars.length)])
      .join();
}

Future<Directory> getTemporaryFolder() async {
  Directory tmpDir = await getTemporaryDirectory();
  var uri = Uri.directory('${tmpDir.path}/io.flown.airdash');
  var dir = Directory.fromUri(uri);
  await dir.create(recursive: true);
  return dir;
}

String formatDataSpeed(int bytes, Duration duration) {
  double seconds = duration.inMilliseconds.toDouble() / 1000;
  var kb = (bytes / 1000) * 8;
  if (kb < 1000) {
    var kbps = (kb / seconds).round();
    return '$kbps kbps';
  } else {
    var mb = kb / 1000;
    var mbps = (mb / seconds).toStringAsFixed(2);
    return '$mbps Mbps';
  }
}

Future<File> getEmptyFile(String filename) async {
  Directory tempDir = await getTemporaryFolder();
  var now = DateTime.now().millisecondsSinceEpoch;
  var file = File("${tempDir.path}/$now/$filename");
  await file.create(recursive: true);
  return file;
}

Map<String, String> errorProps(Object error) {
  return {
    'Error': (error is AppException ? error.type : 'unknownError'),
    'Error Message': error.toString(),
    if (error is AppException) 'Error Info': error.info,
  };
}

Future<Map<String, dynamic>> payloadProperties(Payload payload) async {
  if (payload is UrlPayload) {
    return <String, String>{
      'Type': 'url',
      'URL': payload.httpUrl.toString(),
    };
  } else if (payload is FilePayload) {
    return <String, dynamic>{
      'Type': 'file',
      ...await fileProperties(payload.files),
    };
  } else {
    return <String, dynamic>{
      'Type': 'unknown',
    };
  }
}

Map<String, dynamic> remoteDeviceProperties(Device remote) {
  return <String, String>{
    'Remote Device ID': remote.id,
    'Remote Device Name': remote.name,
    'Remote Device OS': remote.platform ?? '',
    'Remote User ID': remote.userId ?? '',
  };
}

Future<Map<String, dynamic>> fileProperties(List<File> files) async {
  var file = files.firstOrNull;
  if (file == null) {
    ErrorLogger.logSimpleError('noFilesForProps');
    return <String, dynamic>{};
  }
  int fileSize = -1;
  try {
    fileSize = await file.length();
  } catch (error) {
    // Don't log error here. Errors will likely be logged in other places.
    print('Could not get file length $error');
  }
  String filename = file.uri.pathSegments.last;
  return <String, dynamic>{
    'File Count': files.length,
    'File Size': fileSize,
    'File Size MB': fileSize / 1000000,
    'File Name': filename,
    'File Type': lookupMimeType(filename) ?? '',
  };
}

void reportError(String message, Map<String, dynamic> data) {
  var details = FlutterErrorDetails(
    exception: {
      'message': message,
      'data': data,
    },
    library: 'io.flown.airdash',
  );
  FlutterError.reportError(details);
}

String getFilename(File file) {
  return file.uri.pathSegments.last;
}

Future<void> addUsedFile(List<File> files) async {
  var prefs = await SharedPreferences.getInstance();
  var tmpFiles = prefs.getStringList('temporary_files') ?? [];
  for (var file in files) {
    if (!tmpFiles.contains(file.path)) tmpFiles.add(file.path);
    prefs.setStringList('temporary_files', tmpFiles);
  }
  print('HELPER: Used files added ${files.length}');
}

int secondsSince(DateTime date) {
  return DateTime.now().difference(date).inSeconds;
}

extension IterableNullableExtensions<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;

  T? get lastOrNull => isEmpty ? null : last;

  T? tryGet(int index) => index < 0 || index >= length ? null : toList()[index];
}

bool isDesktop() {
  var isWeb = kIsWeb;
  if (isWeb) return false;
  return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
}

bool isMobile() {
  var isWeb = kIsWeb;
  if (isWeb) return false;
  return Platform.isIOS || Platform.isAndroid;
}

MaterialColor createMaterialColor(Color color) {
  var strengths = <double>[.05];
  final swatch = <int, Color>{};
  final int r = color.red, g = color.green, b = color.blue;

  for (int i = 1; i < 10; i++) {
    strengths.add(0.1 * i);
  }
  for (var strength in strengths) {
    final double ds = 0.5 - strength;
    swatch[(strength * 1000).round()] = Color.fromRGBO(
      r + ((ds < 0 ? r : (255 - r)) * ds).round(),
      g + ((ds < 0 ? g : (255 - g)) * ds).round(),
      b + ((ds < 0 ? b : (255 - b)) * ds).round(),
      1,
    );
  }
  return MaterialColor(color.value, swatch);
}

class SingleCompleter<T> {
  var completer = Completer<T>();

  bool get isCompleted {
    return completer.isCompleted;
  }

  Future<T> get future {
    return completer.future;
  }

  void completeError(Object error) {
    if (!completer.isCompleted) {
      completer.completeError(error);
    }
  }

  void complete(T result) {
    if (!completer.isCompleted) {
      completer.complete(result);
    }
  }
}

Future<void> sendPing(Signaling signaling, Device localDevice) async {
  try {
    var transferId = generateId(28);
    var messageSender =
        MessageSender(localDevice, localDevice.id, transferId, signaling);
    logger('PING: Local ping sent');
    await messageSender.sendMessage('localPing', <String, String>{});
  } catch (error) {
    var errorStr = error is GrpcError ? error.code : error.toString();
    logger('PING: Local ping error code: $errorStr');
  }
}

class AnalyticsLogError extends LogError {
  AnalyticsLogError(super.type, [super.error, super.stack, super.context]);
}

class SevereLogError extends LogError {
  SevereLogError(super.type, [super.error, super.stack, super.context]);
}

class LogError implements Exception {
  String type;
  Object? error;
  StackTrace? stack;
  Map<String, dynamic>? context;

  LogError(this.type, [this.error, this.stack, this.context]);

  @override
  String toString() {
    var actual = error != null ? error?.runtimeType : '';
    return '$type $actual'.trim();
  }
}

class AppException implements Exception {
  String type;
  String userError;
  String info = '';

  AppException(this.type, this.userError);

  @override
  String toString() {
    return "AppException: $type";
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}
