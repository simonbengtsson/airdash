import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../helpers.dart';
import '../model/payload.dart';
import '../reporting/error_logger.dart';
import '../reporting/logger.dart';
import 'data_message.dart';

class Receiver {
  RTCPeerConnection connection;

  FileTransferState? currentState;
  Function(Map<String, dynamic>)? onIceCandidate;
  Function(double progress, int totalSize)? statusUpdateCallback;
  SingleCompleter<Payload> waitForPayload = SingleCompleter();

  Function? notifier;

  // Try using negotiated channel instead due to no reply issue
  var useNegotiatedChannel = false;

  Receiver(this.connection);

  static Future<Receiver> create(
      config, Map<String, dynamic> loopbackConstraints) async {
    var connection = await createPeerConnection(config, loopbackConstraints);

    return Receiver(connection);
  }

  Future<Payload> waitForFinish(Function(double, int) callback) {
    statusUpdateCallback = callback;
    return waitForPayload.future;
  }

  processMessage(RTCDataChannel channel, FileTransferState state) async {
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
    await state.tmpFile.writeAsBytes(message.chunk, mode: FileMode.append);
    var writtenLength = message.chunkStart + message.chunk.length;

    var fileCompleted = writtenLength == message.fileSize;
    var json = jsonEncode({
      "version": 1,
      "type": "acknowledge",
      "acknowledgeChunk": message.chunkStart,
      "acknowledgeFile": fileCompleted,
    });
    var ackMessage = RTCDataChannelMessage(json);
    await channel.send(ackMessage);
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
        payload = FilePayload(state.tmpFile);
      }
      waitForPayload.complete(payload);
    } else {
      // Start over in case new messages were received during processing
      processMessage(channel, state);
    }
    print('RECEIVER: Sent ack ${message.chunkStart} $fileCompleted');
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

    connection.onSignalingState = (state) {
      logger('RECEIVER: onSignalingState ${state.name}');
    };
    connection.onConnectionState = (state) async {
      logger('RECEIVER: onConnectionState ${state.name}');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        connection.close();
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        waitForPayload.completeError(AppException(
            "receiverConnectionClosedDuringTransfer",
            'Connection was closed during transfer. Check your internet connection and try again.'));
      }
    };
    connection.onIceGatheringState = (state) {
      logger('RECEIVER: onIceGatheringState ${state.name}');
    };
    connection.onIceConnectionState = (state) async {
      logger('RECEIVER: onIceConnectionState ${state.name}');
    };
    connection.onRenegotiationNeeded = () {
      logger('RECEIVER: onRenegotiationNeeded');
    };

    if (useNegotiatedChannel) {
      connection.onDataChannel = (dataChannel) {
        onDataChannel(dataChannel, firstMessageCompleter);
      };
    } else {
      var dcInit = RTCDataChannelInit();
      dcInit.negotiated = true;
      dcInit.id = 1001;
      var dataChannel =
          await connection.createDataChannel('sendChannel', dcInit);
      onDataChannel(dataChannel, firstMessageCompleter);
    }

    connection.onIceCandidate = (candidate) async {
      var payload = {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex
      };
      var type = candidate.candidate?.split(' ').tryGet(7);
      logger("RECEIVER: New local ice candidate: $type");
      onIceCandidate!(payload);
    };

    await firstMessage;
  }

  onDataChannel(
      RTCDataChannel dataChannel, SingleCompleter firstMessageCompleter) {
    logger('RECEIVER: Data channel received');
    notifier = () async {
      try {
        await processMessage(dataChannel, currentState!);
      } catch (error, stack) {
        ErrorLogger.logStackError(
            'receiverMessageProcessingError', error, stack);
        waitForPayload.completeError('Could not process message');
        connection.close();
      }
    };

    dataChannel.onDataChannelState = (state) {
      logger("RECEIVER: onDataChannelState: ${state.toString()}");
    };

    SingleCompleter? cmp;
    dataChannel.onMessage = (rtcMessage) async {
      try {
        firstMessageCompleter.complete('done');
        handleDataMessage(rtcMessage, dataChannel);
      } catch (error, stack) {
        ErrorLogger.logStackError('receiverMessageParsingError', error, stack);
        waitForPayload.completeError("Could not parse message");
        connection.close();
      }

      cmp?.complete('done');
      cmp = SingleCompleter();
      await cmp!.future.timeout(const Duration(seconds: 20), onTimeout: () {
        waitForPayload.completeError('Receiver data channel timeout');
        connection.close();
      });
    };
  }

  handleDataMessage(
      RTCDataChannelMessage rtcMessage, RTCDataChannel channel) async {
    var message = Message.parse(rtcMessage);
    if (currentState == null) {
      currentState =
          await FileTransferState.create(message.filename, message.meta);
      logger('RECEIVER: New file transfer started');
    }
    currentState!.pendingMessages[message.chunkStart] = message;
    notifier!();
  }

  createAnswer(offerSdp, offerType) async {
    var remoteDesc = RTCSessionDescription(offerSdp, offerType);
    await connection.setRemoteDescription(remoteDesc);
    var answerDesc = await connection.createAnswer();
    await connection.setLocalDescription(answerDesc);
    logger("RECEIVER: Answer created and set ${answerDesc.type}");

    var payload = {
      "sdp": answerDesc.sdp,
      "type": answerDesc.type,
    };
    return payload;
  }

  addIceCandidate(Map<String, dynamic> data) async {
    try {
      String candidate = data['candidate'];
      String sdpMid = data['sdpMid'];
      int sdpMLineIndex = data['sdpMLineIndex'];
      var ic = RTCIceCandidate(candidate, sdpMid, sdpMLineIndex);
      await connection.addCandidate(ic);
      var type = candidate.split(' ').tryGet(7);
      logger("RECEIVER: Added remote ice candidate $type");
    } catch (err) {
      logger("RECEIVER: Add ice candidate error: ${err.toString()}");
    }
  }
}

class FileTransferState {
  Map<int, Message> pendingMessages = {};
  Message? lastHandledMessage;
  var processingMessage = false;

  String filename;
  Map<String, dynamic> meta;
  File tmpFile;

  FileTransferState(this.filename, this.tmpFile, this.meta);

  static Future<FileTransferState> create(
      String filename, Map<String, dynamic> meta) async {
    var file = await getEmptyFile(filename);
    addUsedFile(file);
    return FileTransferState(filename, file, meta);
  }
}
