import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'helpers.dart';
import 'model/payload.dart';
import 'reporting/error_logger.dart';
import 'reporting/logger.dart';

class IntentReceiver {
  StreamSubscription? intentDataStreamSubscription;
  StreamSubscription? intentTextStreamSubscription;

  observe(Function(Payload? payload, String? error) callback) async {
    logger('MAIN: Started observing file intent');
    if (Platform.isIOS) {
      const eventChannel = EventChannel('io.flown.airdash/event_communicator');
      eventChannel.receiveBroadcastStream().listen((event) async {
        var urls = event as List<String>;
        var url = urls.tryGet(0);
        if (url == null) return;

        if (url.startsWith('http')) {
          var parsed = Uri.parse(url);
          callback(UrlPayload(parsed), null);
        } else {
          if (url.startsWith('file://')) {
            url = url.replaceFirst('file://', '');
          }
          var decoded = Uri.decodeFull(url);
          var file = File(decoded);

          if (await file.exists()) {
            callback(FilePayload(file), null);
          } else {
            callback(null, 'Could not read the provided file');
            ErrorLogger.logSimpleError('fileIntentFileNotFoundError', {
              'path': file.path,
            });
          }
        }
      }, onError: (error, StackTrace stack) {
        callback(null, 'Could not handle the provided file');
        ErrorLogger.logStackError('fileIntentError', error, stack);
      });
    } else {
      intentTextStreamSubscription =
          ReceiveSharingIntent.getTextStream().listen((String text) async {
        print('INTENT: Received text $text');
        handleText(text, callback);
      });
      intentDataStreamSubscription = ReceiveSharingIntent.getMediaStream()
          .listen((List<SharedMediaFile> list) async {
        logger('INTENT: Handle intent ${list.length}');
        if (list.isNotEmpty) {
          var file = File(list.first.path);
          logger('MAIN: Handle intent file ${file.path}');
          if (await file.exists()) {
            callback(FilePayload(file), null);
          } else {
            ErrorLogger.logSimpleError('intentReceiverFileNotFound', {
              'path': file.path,
            });
            callback(null, 'Could not read the provided file');
          }
        }
      }, onError: (error, StackTrace stack) {
        ErrorLogger.logStackError('intentReceiverError', error, stack);
        callback(null, 'Could not handle the provided file');
      });

      ReceiveSharingIntent.getInitialMedia()
          .then((List<SharedMediaFile> list) async {
        logger('MAIN: Init intent ${list.length}');
        if (list.isNotEmpty) {
          var file = File(list.first.path);
          logger('MAIN: Init intent file ${file.path}');
          callback(FilePayload(file), null);
        }
      });

      ReceiveSharingIntent.getInitialText().then((String? text) async {
        logger('MAIN: Init text intent $text');
        await handleText(text, callback);
      });
    }
  }

  handleText(String? text, Function(Payload?, String?) callback) async {
    if (text == null) return;
    var uri = Uri.tryParse(text);
    if (uri != null && uri.scheme.startsWith('http')) {
      callback(UrlPayload(uri), null);
    } else {
      var file = await getEmptyFile('text.txt');
      await file.writeAsString(text);
      callback(FilePayload(file), null);
    }
  }
}
