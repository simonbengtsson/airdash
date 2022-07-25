import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../helpers.dart';
import '../reporting/error_logger.dart';
import '../reporting/logger.dart';

class DataSender {
  RTCPeerConnection connection;
  RTCDataChannel dataChannel;
  List<RTCIceCandidate> pendingIceCandidates = [];
  Function(Map<String, dynamic>)? onIceCandidate;

  int maximumMessageSize = 16000;

  // Binary message did not work on windows pre flutter-webrtc 0.8.9
  var useBinaryMessage = true;

  FileSendingState senderState;

  DataSender(this.connection, this.dataChannel, this.senderState);

  static Future<DataSender> create(config, File file, Map<String, String> meta,
      Map<String, dynamic> loopbackConstraints) async {
    logger('SENDER: Create connection with "${config['provider']}"');
    var connection = await createPeerConnection(config, loopbackConstraints);

    var dcInit = RTCDataChannelInit();
    dcInit.negotiated = true;
    dcInit.id = 1001;
    var dataChannel = await connection.createDataChannel('sendChannel', dcInit);

    var sendingState = await FileSendingState.create(file, meta);
    return DataSender(connection, dataChannel, sendingState);
  }

  postIceCandidates() async {
    var desc = await connection.getRemoteDescription();
    if (desc == null) {
      // Confirm that the receiver is ready by waiting for answer
      // before sending ice candidates
      return;
    }
    for (var candidate in pendingIceCandidates) {
      var payload = {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex
      };
      var type = candidate.candidate?.split(' ').tryGet(7);
      logger("SENDER: New local ice candidate: $type");
      onIceCandidate!(payload);
    }
  }

  Future updateMaximumMessageSize() async {
    RTCSessionDescription? local = await connection.getLocalDescription();
    RTCSessionDescription? remote = await connection.getRemoteDescription();

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

      RTCDataChannelMessage rtcMessage;
      if (useBinaryMessage) {
        rtcMessage = RTCDataChannelMessage.fromBinary(bytes);
      } else {
        String strPayload = base64.encode(bytes);
        rtcMessage = RTCDataChannelMessage(strPayload);
      }
      await dataChannel.send(rtcMessage);

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
          var exception = AppException('nextBatchSendingTimeout',
              'Lost connection. Check your internet connection on this and the receiving device.');
          exception.info = "Ack chunk ${senderState.acknowledgedChunk ?? -1}";
          senderState.completer.completeError(exception);
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
    var dataChannelOpenCompleter = SingleCompleter();
    var dataChannelReady = dataChannelOpenCompleter.future
        .timeout(const Duration(seconds: 10), onTimeout: () {
      throw AppException("senderWebrtcConnectionFailed",
          "Could not connect to the receiving device. Check your internet connection and try again.");
    });

    connection.onSignalingState = (state) {};
    connection.onConnectionState = (state) async {
      logger('SENDER: onConnectionState ${state.name}');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        connection.close();
      }
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        senderState.completer.completeError('Connection was closed');
      }
    };
    connection.onIceGatheringState = (state) {
      logger('SENDER: onIceGatheringState ${state.name}');
    };
    connection.onIceConnectionState = (state) {
      logger('SENDER: onIceConnectionState ${state.name}');
    };
    connection.onRenegotiationNeeded = () {
      logger('SENDER: onRenegotiationNeeded');
    };

    connection.onIceCandidate = (candidate) async {
      pendingIceCandidates.add(candidate);
      postIceCandidates();
    };

    dataChannel.onMessage = (message) async {
      try {
        await handleChannelMessage(message);
      } catch (error, stack) {
        ErrorLogger.logStackError('senderMessageProcessingError', error, stack);
        senderState.completer.completeError('Error handling message $error');
      }
    };

    dataChannel.onDataChannelState = (state) async {
      logger("SENDER: onDataChannelState: $state");
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        dataChannelOpenCompleter.complete('done');
      }
    };

    await dataChannelReady;
    logger('SENDER: Data channel ready');
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
    print('SENDER: Received ack for chunk: $finishedChunk $fileCompleted');

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

  createOffer() async {
    var offerSdpConstraints = <String, dynamic>{
      'mandatory': {
        'OfferToReceiveAudio': false,
        'OfferToReceiveVideo': false,
      },
      'optional': [],
    };
    RTCSessionDescription description =
        await connection.createOffer(offerSdpConstraints);
    await connection.setLocalDescription(description);
    logger("SENDER: Offer created and set ${description.type}");

    var offer = {
      'type': description.type,
      'sdp': description.sdp,
    };
    return offer;
  }

  setAnswer(Map<String, dynamic> answer) async {
    var desc = RTCSessionDescription(answer['sdp'], answer['type']);
    await connection.setRemoteDescription(desc);
    logger("SENDER: Answer set");

    await updateMaximumMessageSize();
    postIceCandidates();
  }

  percent(part, total) {
    return ((part / total) * 100).round();
  }

  addIceCandidate(Map<String, dynamic> data) async {
    try {
      String candidate = data['candidate'];
      String sdpMid = data['sdpMid'];
      int sdpMLineIndex = data['sdpMLineIndex'];
      var ic = RTCIceCandidate(candidate, sdpMid, sdpMLineIndex);
      await connection.addCandidate(ic);
      var type = candidate.split(' ').tryGet(7);
      logger("SENDER: Added remote ice candidate $type");
    } catch (err) {
      logger("SENDER: Add ice candidate error: ${err.toString()} $data");
    }
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
