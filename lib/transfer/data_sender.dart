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

  // Since buffered amount is only implemented on Android right now in
  // flutter_webrtc a simplified in house version is used instead where only a
  // certain number of messages is in flight without being acknowledge. Around
  // 10 seems to be a good number since fewer results in lower speeds and more
  // does not result in higher speeds and also sometimes crashes the transfer
  // likely due to some kind of buffer overflow.
  var maximumInFlightMessages = 10;

  var inFlightMessageCount = 0;

  int maximumMessageSize = 16000;

  // Binary message did not work on windows pre flutter-webrtc 0.8.9
  var useBinaryMessage = true;

  FileSendingState senderState;

  DataSender(this.peer, this.senderState);

  static Future<DataSender> create(
      Peer peer, File file, Map<String, String> meta) async {
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

  Future sendChunk() async {
    var state = senderState;
    var startByte = await state.raFile.position();
    print("SENDER: Sending chunk: $startByte");

    var message = {
      "version": 1,
      "filename": state.filename,
      "messageSize": maximumMessageSize,
      "chunkStart": startByte,
      "fileSize": state.fileSize,
      "meta": state.meta,
    };

    List<int> header = utf8.encode('${jsonEncode(message)}\n');
    var base64Overhead =
        useBinaryMessage ? 0 : (0.25 * maximumMessageSize).floor();
    var bytesToRead = maximumMessageSize - header.length - base64Overhead;
    var chunk = await state.raFile.read(bytesToRead);
    var isFileRead = startByte + bytesToRead >= state.fileSize;

    var builder = BytesBuilder();
    builder.add(header);
    builder.add(chunk);
    var bytes = builder.toBytes();

    inFlightMessageCount += 1;
    logger('Increased inFlightMessageCount $inFlightMessageCount');

    if (useBinaryMessage) {
      await peer.sendBinary(bytes);
    } else {
      String strPayload = base64.encode(bytes);
      await peer.sendText(strPayload);
    }

    if (isFileRead) {
      logger("SENDER: Last chunk sent");
      state.fileSendingComplete = true;
    }
  }

  Function(int, int)? statusCallback;

  SingleCompleter<bool>? messageTimeoutCompleter;

  Future sendFile(Function(int, int) statusCallback) async {
    this.statusCallback = statusCallback;
    logger('SENDER: Sending first chunk...');
    sendNext();
    await senderState.completer.future;
  }

  Future sendNext() async {
    if (senderState.completer.isCompleted) {
      logger('SENDER: Cancelled sending chunk due to completed');
      return;
    }
    try {
      var state = senderState;
      print("SENDER: Sending chunk for ${state.filename}");

      if (state.fileSendingComplete) {
        logger('SENDER: File sent completed, cancelled');
        return;
      }

      if (inFlightMessageCount >= maximumInFlightMessages) {
        logger('SENDER: Already max massages in flight, cancelled');
        return;
      }

      if (state.sendChunkLock) {
        logger('SENDER: Already sending chunk, cancelled');
        return;
      }
      state.sendChunkLock = true;

      await sendChunk();

      state.sendChunkLock = false;
      if (!state.fileSendingComplete) {
        sendNext();
      }
      messageTimeoutCompleter?.complete(true);
      messageTimeoutCompleter = SingleCompleter();
      await messageTimeoutCompleter!.future.timeout(const Duration(seconds: 10),
          onTimeout: onDataMessageTimeout);
    } catch (error, stack) {
      messageTimeoutCompleter?.complete(true);
      ErrorLogger.logStackError('senderSendError', error, stack);
      senderState.completer.completeError("Could not send chunk '$error'");
    }
  }

  bool onDataMessageTimeout() {
    if (senderState.acknowledgedChunk == null) {
      var exception = AppException('firstDataMessageTimeout',
          'Connection was successful, but data transfer failed. This could be an issue with the app.');
      senderState.completer.completeError(exception);
    } else {
      var exception = AppException('nextBatchSendingTimeout',
          'Lost connection. Check your internet connection on this and the receiving device.');
      exception.info = "Ack chunk ${senderState.acknowledgedChunk ?? -1}";
      senderState.completer.completeError(exception);
    }
    return true;
  }

  Future connect() async {
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

  Future handleChannelMessage(RTCDataChannelMessage message) async {
    var json = jsonDecode(message.text) as Map<String, dynamic>;
    var type = json['type'] as String;
    if (type != 'acknowledge') {
      logger("Unknown message ${message.text}");
      return;
    }
    var finishedChunk = json['acknowledgeChunk'] as int;
    var fileCompleted = json['acknowledgeFile'] as bool;

    var ackChunk = senderState.acknowledgedChunk;
    if (ackChunk != null && finishedChunk <= ackChunk) {
      return; // No need to handle old ack
    }
    senderState.acknowledgedChunk = finishedChunk;
    inFlightMessageCount -= 1;
    logger('decreaed inFlightMessageCount $inFlightMessageCount');
    print(
        'SENDER: Received ack for chunk: $finishedChunk Completed: $fileCompleted');

    if (statusCallback != null &&
        !senderState.completer.completer.isCompleted) {
      statusCallback!(finishedChunk, senderState.fileSize);
    }

    if (!fileCompleted) {
      print('SENDER: Sending next chunk...');
      sendNext();
    } else {
      logger("SENDER: File successfully sent and acknowledged");
      senderState.completer.complete('done');
    }
  }

  num percent(num part, num total) {
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

  var completer = SingleCompleter<String>();
  var fileSendingComplete = false;
  var sendChunkLock = false;

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
