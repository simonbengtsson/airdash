import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:simple_peer/simple_peer.dart';

import '../helpers.dart';
import '../reporting/error_logger.dart';
import '../reporting/logger.dart';

class DataSender {
  Peer peer;

  int maximumMessageSize = 16000;

  // Binary message did not work on windows pre flutter-webrtc 0.8.9
  var useBinaryMessage = true;

  FileSendingState senderState;

  DataSender(this.peer, this.senderState);

  static Future<DataSender> create(
      peer, File file, Map<String, String> meta) async {
    logger('SENDER: Create connection');

    var sendingState = await FileSendingState.create(file, meta);
    return DataSender(peer, sendingState);
  }

  Future updateMaximumMessageSize() async {
    RTCSessionDescription? local = await peer.connection.getLocalDescription();
    RTCSessionDescription? remote =
        await peer.connection.getRemoteDescription();

    int localMaximumSize = parseMaximumSize(local);
    int remoteMaximumSize = parseMaximumSize(remote);
    int messageSize = min(localMaximumSize, remoteMaximumSize);

    logger(
        'SENDER: Updated max message size: $messageSize Local: $localMaximumSize Remote: $remoteMaximumSize ');
    maximumMessageSize = messageSize;
  }

  int parseMaximumSize(RTCSessionDescription? description) {
    var remoteLines = description?.sdp?.split('\r\n') ?? [];

    int remoteMaximumSize = 0;
    for (final line in remoteLines) {
      if (line.startsWith('a=max-message-size:')) {
        var string = line.substring('a=max-message-size:'.length);
        remoteMaximumSize = int.parse(string);
        break;
      }
    }

    if (remoteMaximumSize == 0) {
      logger('SENDER: No max message size session description');
    }

    // 16 kb should be supported on all clients so we can use it
    // even if no max message is set
    return max(remoteMaximumSize, maximumMessageSize);
  }

  Future sendNextBatch() async {
    var state = senderState;
    print("SENDER: Sending batch for ${state.filename}");

    if (state.sendBatchLock) {
      print('SENDER: Busy sending, continue later');
      return;
    }
    if (state.fileSendingComplete) {
      logger('SENDER: File sent completed, cancelled sending');
      return;
    }
    state.sendBatchLock = true;

    int messageSize = maximumMessageSize;
    var startByte = await state.raFile.position();

    var bufferLimit = (state.acknowledgedChunk ?? 0) + messageSize * 10;
    if (startByte >= bufferLimit) {
      print(
          'SENDER: Not sending next batch right now, lacking ack. Want to send $startByte, acked chunk: ${state.acknowledgedChunk} buffer limit: $bufferLimit');
      state.sendBatchLock = false;
      return;
    }

    print("SENDER: Sending batch: $startByte size: $messageSize");
    for (int i = 0; i < 10; i++) {
      var startByte = await state.raFile.position();

      var message = {
        "version": 1,
        "filename": state.filename,
        "messageSize": messageSize,
        "chunkStart": startByte,
        "fileSize": state.fileSize,
        "meta": state.meta,
      };

      List<int> header = utf8.encode('${jsonEncode(message)}\n');
      var base64Overhead = useBinaryMessage ? 0 : (0.25 * messageSize).floor();
      var bytesToRead = messageSize - header.length - base64Overhead;
      var chunk = await state.raFile.read(bytesToRead);
      var isFileRead = startByte + bytesToRead >= state.fileSize;

      var builder = BytesBuilder();
      builder.add(header);
      builder.add(chunk);
      var bytes = builder.toBytes();

      if (useBinaryMessage) {
        await peer.sendBinary(bytes);
      } else {
        String strPayload = base64.encode(bytes);
        await peer.sendText(strPayload);
      }

      if (isFileRead) {
        logger("SENDER: Last chunk sent");
        state.fileSendingComplete = true;
        break;
      }
    }

    state.sendBatchLock = false;

    if (!state.fileSendingComplete) {
      notifier!();
    }
  }

  Function()? notifier;
  Function(int, int)? statusCallback;

  SingleCompleter? batchTimeoutCompleter;

  sendFile(Function(int, int) statusCallback) async {
    this.statusCallback = statusCallback;
    notifier = () async {
      if (senderState.completer.completer.isCompleted) {
        logger('SENDER: Cancelled next batch due to completed');
        return;
      }
      try {
        await sendNextBatch();
        batchTimeoutCompleter?.complete('done');
        batchTimeoutCompleter = SingleCompleter();
        batchTimeoutCompleter!.future.timeout(const Duration(seconds: 10),
            onTimeout: () {
          if (senderState.acknowledgedChunk == null) {
            var exception = AppException('firstDataMessageTimeout',
                'Connection was successful, but data transfer failed. This could be an issue with the app. Report Issue');
            senderState.completer.completeError(exception);
          } else {
            var exception = AppException('nextBatchSendingTimeout',
                'Lost connection. Check your internet connection on this and the receiving device.');
            exception.info = "Ack chunk ${senderState.acknowledgedChunk ?? -1}";
            senderState.completer.completeError(exception);
          }
        });
      } catch (error, stack) {
        batchTimeoutCompleter?.complete('done');
        ErrorLogger.logStackError('senderSendError', error, stack);
        senderState.completer.completeError("Could not send batch '$error'");
      }
    };
    logger('SENDER: Sending first batch...');
    notifier!();
    await senderState.completer.future;
  }

  connect() async {
    peer.onBinaryData = (bytes) async {
      try {
        var message = RTCDataChannelMessage.fromBinary(bytes);
        await handleChannelMessage(message);
      } catch (error, stack) {
        ErrorLogger.logStackError('senderMessageProcessingError', error, stack);
        senderState.completer.completeError('Error handling message $error');
      }
    };
    peer.onTextData = (text) async {
      try {
        var message = RTCDataChannelMessage(text);
        await handleChannelMessage(message);
      } catch (error, stack) {
        ErrorLogger.logStackError('senderMessageProcessingError', error, stack);
        senderState.completer.completeError('Error handling message $error');
      }
    };

    peer.connection.onConnectionState = (state) async {
      logger('SENDER: onConnectionState ${state.name}');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        peer.connection.close();
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        senderState.completer.completeError('Connection was closed');
      }
    };

    await peer.connect().timeout(const Duration(seconds: 10), onTimeout: () {
      throw AppException("senderWebrtcConnectionFailed",
          "Could not connect to the receiving device. Check your internet connection and try again.");
    });

    await updateMaximumMessageSize();
    logger('SENDER: Peer was connected and data channel ready');
  }

  handleChannelMessage(RTCDataChannelMessage message) async {
    Map<String, dynamic> json = jsonDecode(message.text);
    String type = json['type'];
    if (type != 'acknowledge') {
      logger("Unknown message ${message.text}");
      return;
    }
    int finishedChunk = json['acknowledgeChunk'];
    bool fileCompleted = json['acknowledgeFile'];

    var ackChunk = senderState.acknowledgedChunk;
    if (ackChunk != null && finishedChunk <= ackChunk) {
      return; // No need to handle old ack
    }
    senderState.acknowledgedChunk = finishedChunk;
    print(
        'SENDER: Received ack for chunk: $finishedChunk Completed: $fileCompleted');

    if (statusCallback != null &&
        !senderState.completer.completer.isCompleted) {
      statusCallback!(finishedChunk, senderState.fileSize);
    }

    if (!fileCompleted) {
      print('SENDER: Sending next batch...');
      notifier!();
    } else {
      logger("SENDER: File successfully sent and acknowledged");
      senderState.completer.complete('done');
    }
  }

  percent(part, total) {
    return ((part / total) * 100).round();
  }
}

class FileSendingState {
  File file;
  RandomAccessFile raFile;
  Map<String, String> meta;
  int fileSize;
  String filename;

  int? acknowledgedChunk;

  var completer = SingleCompleter();
  var fileSendingComplete = false;
  var sendBatchLock = false;

  FileSendingState(
      this.file, this.raFile, this.filename, this.fileSize, this.meta);

  static Future<FileSendingState> create(
      File file, Map<String, String> meta) async {
    var name = file.uri.pathSegments.last;
    var size = await file.length();
    var raFile = await file.open();
    return FileSendingState(file, raFile, name, size, meta);
  }
}
