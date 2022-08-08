import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:simple_peer/simple_peer.dart';

import '../helpers.dart';
import '../model/payload.dart';
import '../reporting/error_logger.dart';
import '../reporting/logger.dart';
import 'data_message.dart';

class Receiver {
  Peer peer;
  FileTransferState? currentState;
  Function(double progress, int totalSize)? statusUpdateCallback;
  SingleCompleter<Payload> waitForPayload = SingleCompleter();

  Function? notifier;

  // Try using negotiated channel instead due to no reply issue
  var useNegotiatedChannel = false;

  Receiver(this.peer);

  static Future<Receiver> create(Peer peer) async {
    return Receiver(peer);
  }

  Future<Payload> waitForFinish(Function(double, int) callback) {
    statusUpdateCallback = callback;
    return waitForPayload.future;
  }

  processMessage() async {
    var state = currentState!;

    if (state.processingMessage) {
      print('RECEIVER: Skipping, already processing message');
      return;
    }
    state.processingMessage = true;

    var nextChunk = 0;
    var lastMessage = state.lastHandledMessage;
    if (lastMessage != null) {
      nextChunk = lastMessage.chunkStart + lastMessage.chunk.length;
    }

    var message = state.pendingMessages[nextChunk];
    if (message == null) {
      // The next chunk is not transferred yet
      print('RECEIVER: Waiting, $nextChunk chunk not available');
      state.processingMessage = false;
      return;
    }

    if (state.filename != message.filename) {
      // Improve same file check
      logger("RECEIVER: Ignoring new file since transfer already in progress");
      state.processingMessage = false;
      return;
    }

    print(
        'RECEIVER: Chunk received ${message.chunkStart} of ${message.fileSize} of ${message.filename}');
    var tmpFile = await state.tmpFile();
    await tmpFile.writeAsBytes(message.chunk, mode: FileMode.append);
    var writtenLength = message.chunkStart + message.chunk.length;

    var fileCompleted = writtenLength == message.fileSize;
    var json = jsonEncode({
      "version": 1,
      "type": "acknowledge",
      "acknowledgeChunk": message.chunkStart,
      "acknowledgeFile": fileCompleted,
    });
    await peer.sendText(json);
    statusUpdateCallback?.call(
        writtenLength / message.fileSize, message.fileSize);
    state.pendingMessages.remove(nextChunk);

    state.lastHandledMessage = message;
    state.processingMessage = false;

    if (fileCompleted) {
      logger("RECEIVER: File received: ${message.filename}");
      currentState = null;
      Payload payload;
      var url = state.meta['url'];
      if (url != null) {
        payload = UrlPayload(Uri.parse(url));
      } else {
        payload = FilePayload(tmpFile);
      }
      waitForPayload.complete(payload);
    } else {
      // Start over in case new messages were received during processing
      processMessage();
    }
    print(
        'RECEIVER: Sent ack for chunk ${message.chunkStart}-${message.chunkStart + message.chunk.length}. Completed: $fileCompleted');
  }

  connect() async {
    var firstMessageCompleter = SingleCompleter();
    // Use a higher timeout than sender so that errors are originated from
    // sender if possible
    var firstMessage = firstMessageCompleter.future
        .timeout(const Duration(seconds: 20), onTimeout: () {
      throw AppException("receiverWebrtcConnectionFailed",
          "Could not connect to sending device. Check your internet connection and try again.");
    });

    await peer.connect();

    peer.connection.onConnectionState = (state) async {
      logger('RECEIVER: onConnectionState ${state.name}');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        await peer.connection.close();
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        waitForPayload.completeError(AppException(
            "receiverConnectionClosedDuringTransfer",
            'Connection was closed during transfer. Check your internet connection and try again.'));
      }
    };

    logger('RECEIVER: Data channel received');
    notifier = () async {
      try {
        await processMessage();
      } catch (error, stack) {
        ErrorLogger.logStackError(
            'receiverMessageProcessingError', error, stack);
        waitForPayload.completeError('Could not process message');
        peer.connection.close();
      }
    };

    SingleCompleter? cmp;
    peer.onBinaryData = (bytes) async {
      try {
        firstMessageCompleter.complete('done');
        await handleDataMessage(bytes);
      } catch (error, stack) {
        ErrorLogger.logStackError('receiverMessageParsingError', error, stack);
        waitForPayload.completeError("Could not parse message");
        peer.connection.close();
      }

      cmp?.complete('done');
      cmp = SingleCompleter();
      await cmp!.future.timeout(const Duration(seconds: 20), onTimeout: () {
        waitForPayload.completeError('Receiver data channel timeout');
        peer.connection.close();
      });
    };
    peer.onTextData = (text) async {
      try {
        firstMessageCompleter.complete('done');
        List<int> bytes = base64.decode(text);
        await handleDataMessage(bytes);
      } catch (error, stack) {
        ErrorLogger.logStackError('receiverMessageParsingError', error, stack);
        waitForPayload.completeError("Could not parse message");
        peer.connection.close();
      }

      cmp?.complete('done');
      cmp = SingleCompleter();
      await cmp!.future.timeout(const Duration(seconds: 20), onTimeout: () {
        waitForPayload.completeError('Receiver data channel timeout');
        peer.connection.close();
      });
    };

    await firstMessage;
  }

  handleDataMessage(List<int> bytes) async {
    print('Handling data message');
    var message = Message.parse(bytes);
    if (currentState == null) {
      currentState = FileTransferState(message.filename, message.meta);
      logger('RECEIVER: New file transfer started');
    }
    currentState!.pendingMessages[message.chunkStart] = message;
    notifier!();
  }
}

class FileTransferState {
  Map<int, Message> pendingMessages = {};
  Message? lastHandledMessage;
  var processingMessage = false;

  String filename;
  Map<String, dynamic> meta;

  File? _tmpFile;
  Future<File> tmpFile() async {
    if (_tmpFile == null) {
      _tmpFile = await getEmptyFile(filename);
      addUsedFile(_tmpFile!);
    }
    return _tmpFile!;
  }

  FileTransferState(this.filename, this.meta);
}
