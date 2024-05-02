import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'helpers.dart';
import 'model/payload.dart';
import 'reporting/error_logger.dart';
import 'reporting/logger.dart';

class IntentReceiver {
  StreamSubscription<dynamic>? intentDataStreamSubscription;
  StreamSubscription<dynamic>? intentTextStreamSubscription;

  Future<void> observe(
      Function(Payload? payload, String? error) callback) async {
    logger('MAIN: Started observing file intent');
    if (Platform.isIOS) {
      const eventChannel = EventChannel('io.flown.airdash/event_communicator');
      eventChannel.receiveBroadcastStream().listen((event) async {
        List<File> files = [];
        for (String url in List<String>.from(event as List? ?? [])) {
          if (url.startsWith('http')) {
            var parsed = Uri.parse(url);
            callback(UrlPayload(parsed), null);
            return;
          } else {
            if (url.startsWith('file://')) {
              url = url.replaceFirst('file://', '');
            }
            var decoded = Uri.decodeFull(url);
            var file = File(decoded);

            if (await file.exists()) {
              files.add(file);
            } else {
              callback(null, 'Could not read the provided file');
              ErrorLogger.logSimpleError(
                  'fileIntentFileNotFoundError', <String, String>{
                'path': file.path,
              });
              return;
            }
          }
          callback(FilePayload(files), null);
        }
      }, onError: (Object error, StackTrace stack) {
        callback(null, 'Could not handle the provided file');
        ErrorLogger.logStackError('fileIntentError', error, stack);
      });
    } else {
      intentTextStreamSubscription = ReceiveSharingIntent.instance
          .getMediaStream()
          .listen((content) async {
        print('INTENT: Received text $content');
        //handleText(text, callback);
      });
      intentDataStreamSubscription = ReceiveSharingIntent.instance
          .getMediaStream()
          .listen((List<SharedMediaFile> list) async {
        logger('INTENT: Handle intent ${list.length}');
        if (list.isNotEmpty) {
          var files = list.map((it) => File(it.path)).toList();
          for (var file in files) {
            if (await file.exists()) {
              ErrorLogger.logSimpleError(
                  'intentReceiverFileNotFound', <String, dynamic>{
                'firstPath': files.first.path,
                'count': files.length,
              });
              callback(null, 'Could not read the provided file');
              return;
            }
          }
          callback(FilePayload(files), null);
          logger('MAIN: Handle intent file ${files.length}');
        }
      }, onError: (Object error, StackTrace stack) {
        ErrorLogger.logStackError('intentReceiverError', error, stack);
        callback(null, 'Could not handle the provided file');
      });

      ReceiveSharingIntent.instance
          .getInitialMedia()
          .then((List<SharedMediaFile> list) async {
        logger('MAIN: Init intent ${list.length}');
        if (list.isNotEmpty) {
          var files = list.map((it) => File(it.path)).toList();
          logger('MAIN: Init intent files ${files.length}');
          callback(FilePayload(files), null);
        }
      });

      ReceiveSharingIntent.instance.getInitialMedia().then((content) async {
        logger('MAIN: Init text intent $content');
        //await handleText(content, callback);
      });
    }
  }

  Future<void> handleText(
      String? text, Function(Payload?, String?) callback) async {
    if (text == null) return;
    var uri = Uri.tryParse(text);
    if (uri != null && uri.scheme.startsWith('http')) {
      callback(UrlPayload(uri), null);
    } else {
      var file = await getEmptyFile('text.txt');
      await file.writeAsString(text);
      callback(FilePayload([file]), null);
    }
  }
}
