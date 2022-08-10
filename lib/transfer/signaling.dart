import 'dart:async';

import 'package:firedart/firedart.dart';

import '../helpers.dart';
import '../model/device.dart';
import '../reporting/error_logger.dart';
import '../reporting/logger.dart';

class Signaling {
  CallbackErrorState? callbackErrorState;
  MissingPingErrorState? missingPingErrorState;
  DateTime? lastSignalingMessageReceived;

  List<String> sentErrors = [];

  Timer? observerTimer;
  StreamSubscription? _messagesStream;

  var receivedMessages = {};

  Future observe(Device localDevice,
      Function(String message, String senderId) onMessage) async {
    restartListen(localDevice, onMessage);
  }

  restartListen(Device localDevice, Function onMessage) {
    _messagesStream?.cancel();
    _messagesStream = Firestore.instance
        .collection('messages')
        .document(localDevice.id)
        .collection('messages')
        .stream
        .listen((docs) async {
      lastSignalingMessageReceived = DateTime.now();
      var state = callbackErrorState;
      if (state != null) {
        ErrorLogger.logSimpleError(
            'observerCallbackErrorRecovery',
            {
              'errorCount': state.callbackErrors.length,
              'startedAt': state.startedAt.toIso8601String(),
              'lastErrorAt': state.lastErrorAt.toIso8601String(),
              'errors': state.callbackErrors.map((e) => e.toString()),
            },
            1);
        callbackErrorState = null;
      }
      if (missingPingErrorState != null) {
        ErrorLogger.logSimpleError(
            'observerMissingPingRecovery',
            {
              'callbackErrorState': state != null,
              'errors': missingPingErrorState!.restartCount,
            },
            1);
        missingPingErrorState = null;
      }

      try {
        await _handleDocs(docs, onMessage);
      } catch (error, stack) {
        ErrorLogger.logStackError('signaling_handlingDocsError', error, stack);
      }
    }, onError: (Object error, StackTrace stack) async {
      if (callbackErrorState == null) {
        callbackErrorState = CallbackErrorState();
        callbackErrorState!.callbackErrors.add(error);
        ErrorLogger.logStackError(
            'observerError_callbackError', error, stack, 1);
      } else {
        callbackErrorState!.lastErrorAt = DateTime.now();
        callbackErrorState!.callbackErrors.add(error);
        print('SIGNALING: Added new callback error to error state');
      }

      // Delay to not cause infinite quick restarts in case of
      // immediate error
      await Future.delayed(const Duration(seconds: 5));
      restartListen(localDevice, onMessage);
      // Send ping to get message quickly in case connection is restored
      sendPing(this, localDevice);
    });
    logger('RECEIVER: Listening for files...');

    observerTimer?.cancel();
    observerTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      int? lastReceived = lastSignalingMessageReceived?.millisecondsSinceEpoch;
      var now = DateTime.now().millisecondsSinceEpoch;

      // We should get a ping every 60 seconds so if we have not in 100
      // seconds restart observer.
      if (lastReceived == null || now - lastReceived > 5 * 60 * 1000 + 10) {
        var callbackError = callbackErrorState;
        if (callbackError == null ||
            secondsSince(callbackError.lastErrorAt) > 10) {
          logger(
              'SIGNALING: No error or ping received recently, restarting observer...');
          if (missingPingErrorState == null) {
            ErrorLogger.logSimpleError('observerError_missingPing', null, 1);
            missingPingErrorState = MissingPingErrorState();
          }
          missingPingErrorState!.restartCount += 1;
          restartListen(localDevice, onMessage);
          // Send ping to get message quickly in case connection is restored
          sendPing(this, localDevice);
        }
      }
    });
  }

  Future _handleDocs(docs, onMessage) async {
    for (var doc in docs) {
      if (receivedMessages[doc.id] != null) {
        continue;
      }
      receivedMessages[doc.id] = true;

      var data = doc.map;
      var date = data['date'] as DateTime;
      var message = data['message'] as String;
      var senderId = data['senderId'] as String;

      if (date.millisecondsSinceEpoch <
          DateTime.now().millisecondsSinceEpoch - 15000) {
        var diff =
            DateTime.now().millisecondsSinceEpoch - date.millisecondsSinceEpoch;
        logger(
            'SIGNALING: Removing old message $message $senderId ${date.millisecondsSinceEpoch} $diff');
        await doc.reference.delete();
        continue;
      }

      onMessage(message, senderId);
      await doc.reference.delete();
    }
  }

  sendMessage(String senderId, String receiverId, String message) async {
    var doc = await Firestore.instance
        .collection('messages')
        .document(receiverId)
        .collection('messages')
        .add({
      'date': DateTime.now(),
      'senderId': senderId,
      'receiverId': receiverId,
      'message': message,
      // Versioning is moved to connector.dart, but keep this for a while
      'version': 3,
    });
    return doc.id;
  }
}

class CallbackErrorState {
  DateTime startedAt = DateTime.now();
  DateTime lastErrorAt = DateTime.now();
  List<Object> callbackErrors = [];
}

class MissingPingErrorState {
  DateTime startedAt = DateTime.now();
  int restartCount = 1;
}
