import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock/wakelock.dart';

import '../helpers.dart';
import '../model/device.dart';
import '../model/payload.dart';
import '../reporting/analytics_logger.dart';
import '../reporting/error_logger.dart';
import '../reporting/logger.dart';
import '../transfer/data_receiver.dart';
import '../transfer/data_sender.dart';
import '../transfer/signaling.dart';

typedef Json = Map<String, dynamic>;

class Connector {
  final loopbackConstraints = <String, dynamic>{
    'mandatory': {},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ],
  };

  Device localDevice;
  SignalingObserver observer;
  Signaling signaling;

  String? activeTransferId;

  Connector(this.localDevice, this.signaling, this.observer);

  static Connector create(Device localDevice) {
    var signaling = Signaling();
    var observer = SignalingObserver(localDevice.id, signaling);
    return Connector(localDevice, signaling, observer);
  }

  sendFile(Device receiver, List<Payload> payloads,
      Function(int, int) statusCallback) async {
    var payload = payloads.first;

    File file;
    Map<String, String> meta;
    if (payload is FilePayload) {
      file = payload.file;
      meta = {'type': 'file'};
    } else if (payload is UrlPayload) {
      file = await getEmptyFile('url.txt');
      await file.writeAsString(payload.httpUrl.toString());
      meta = {'type': 'url', 'url': payload.httpUrl.toString()};
    } else {
      throw Exception('Invalid payload type');
    }

    logger('SENDER: Start sending file to receiver "${receiver.id}"');
    logger('SENDER: File ${file.path}');
    var startTime = DateTime.now();

    if (Platform.isIOS) {
      communicatorChannel.invokeMethod('startFileSending', {});
    }
    logger('SENDER: Started background task');

    DataSender? sender;
    Object? sendError;
    var transferId = generateId(28);
    activeTransferId = transferId;

    var payloadProps = await payloadProperties(payloads);
    AnalyticsEvent.sendingStarted.log({
      'Transfer ID': transferId,
      ...remoteDeviceProperties(receiver),
      ...payloadProps,
    });
    try {
      await Wakelock.enable();
      logger('SENDER: Start transfer $transferId');

      var messageSender =
          MessageSender(localDevice, receiver.id, transferId, signaling);
      var config = await getIceServerConfig();
      sender = await DataSender.create(config, file, meta, loopbackConstraints);
      observer.onAnswer = (answer) {
        sender!.setAnswer(answer);
      };
      observer.onReceiverIceCandidate = (candidate) {
        sender!.addIceCandidate(candidate);
      };
      sender.onIceCandidate = (candidate) {
        messageSender.sendMessage('senderIceCandidate', candidate);
      };
      await googlePing();
      var completer = SingleCompleter();
      messageSender.sendMessage('ping', {});
      observer.onPingResponse = (remoteVersion) {
        if (remoteVersion == MessageSender.communicationVersion) {
          completer.complete('done');
        } else {
          var error = AppException('senderVersionMismatch',
              'Transfer failed. Update to the latest app version on both the sending and receiving devices.');
          completer.completeError(error);
        }
      };
      await completer.future.timeout(const Duration(seconds: 5), onTimeout: () {
        throw AppException('deviceFirebasePingTimeout',
            'Could not reach the receiving device. Ensure it is connected to the internet and has AirDash open.');
      });
      var future = sender.connect();
      var offer = await sender.createOffer();
      await messageSender.sendMessage('offer', offer);
      logger('SENDER: Sent offer, waiting for connection...');
      await future;
      logger('SENDER: Connection established');
      await sender.sendFile(statusCallback);
    } catch (error) {
      sendError = error;
      rethrow;
    } finally {
      await Wakelock.disable();
      List<String> connectionTypes = [];
      if (sender != null) {
        connectionTypes = await getConnectionTypes(sender.connection);
        logger('SENDER: Finished with $connectionTypes');
        await sender.connection.close();
        await sender.senderState.raFile.close();
      }
      observer.onAnswer = null;
      observer.onReceiverIceCandidate = null;
      observer.onPingResponse = null;
      activeTransferId = null;
      signaling.receivedMessages = {};
      if (Platform.isIOS) {
        communicatorChannel.invokeMethod('endFileSending', {});
      }
      logger('SENDER: Connector cleaned up');

      AnalyticsEvent.sendingCompleted.log({
        'Duration': DateTime.now().difference(startTime).inSeconds.abs(),
        'Success': sendError == null,
        'Transfer ID': transferId,
        'Connection Types': connectionTypes,
        if (sendError != null) ...errorProps(sendError),
        ...remoteDeviceProperties(receiver),
        ...payloadProps,
      });
    }
  }

  saveDeviceInfo(Device device) async {
    var prefs = await SharedPreferences.getInstance();
    var list = prefs.getStringList('receivers') ?? [];
    var devices = list.map((r) => Device.decode(jsonDecode(r))).toList();
    devices.removeWhere((element) => element.id == device.id);
    devices.add(device);
    await prefs.setStringList(
        'receivers', devices.map((r) => jsonEncode(r.encode())).toList());
  }

  googlePing() async {
    try {
      await http
          .get(Uri.parse('https://www.google.com'))
          .timeout(const Duration(seconds: 5));
      logger('SENDER: Google ping succeeded');
    } catch (error) {
      throw AppException('googlePingFailed',
          'Could not connect to internet. Check your connection and try again.');
    }
  }

  receiveFile(
      String localId,
      String remoteId,
      String transferId,
      Map<String, dynamic> offer,
      Function(Payload? payload, Object? error, String message)
          callback) async {
    activeTransferId = transferId;
    logger('RECEIVER: Starting receiving');
    callback(null, null, 'Connecting...');

    var prefs = await SharedPreferences.getInstance();
    var list = prefs.getStringList('receivers') ?? [];
    var devices = list.map((r) => Device.decode(jsonDecode(r))).toList();
    var sender = devices.where((element) => element.id == remoteId).firstOrNull;

    if (sender == null) {
      ErrorLogger.logSimpleError('Receiving file from unknown sender');
    }

    AnalyticsEvent.receivingStarted.log({
      'Transfer ID': transferId,
      if (sender != null) ...remoteDeviceProperties(sender),
    });

    Payload? receivePayload;
    Object? receiveError;
    Receiver? receiver;
    try {
      await Wakelock.enable();
      var messageSender =
          MessageSender(localDevice, remoteId, transferId, signaling);
      var config = await getIceServerConfig();
      var receiver = await Receiver.create(config, loopbackConstraints);
      receiver.onIceCandidate = (candidate) {
        messageSender.sendMessage('receiverIceCandidate', candidate);
      };
      observer.onSenderIceCandidate = (candidate) {
        receiver.addIceCandidate(candidate);
      };
      var future = receiver.connect();
      var answer = await receiver.createAnswer(offer['sdp'], offer['type']);
      await messageSender.sendMessage('answer', answer);
      await future;
      String? lastProgressStr;
      var payload = await receiver.waitForFinish((progress, totalSize) {
        var payloadMbSize = totalSize / 1000000;
        var fractionDigits = payloadMbSize > 1000 ? 1 : 0;
        var progressStr = (progress * 100).toStringAsFixed(fractionDigits);
        if (lastProgressStr != progressStr) {
          var message = 'Receiving $progressStr%...';
          callback(null, null, message);
          lastProgressStr = progressStr;
        }
      });
      receivePayload = payload;
      callback(payload, null, '');
    } catch (error, stack) {
      receiveError = error;
      if (error is AppException) {
        ErrorLogger.logError(LogError(error.type, error, stack));
      } else {
        ErrorLogger.logStackError('unknownReceiverError', error, stack);
      }
      callback(null, error, '');
    } finally {
      List<String> connectionTypes = [];
      if (receiver != null) {
        connectionTypes = await getConnectionTypes(receiver.connection);
        logger('RECEIVER: Finished with $connectionTypes');
      }
      await Wakelock.disable();
      await receiver?.connection.close();
      observer.onSenderIceCandidate = null;
      activeTransferId = null;
      signaling.receivedMessages = {};
      logger('RECEIVER: Receiver cleanup finished');

      AnalyticsEvent.receivingCompleted.log({
        'Success': receiveError == null,
        'Remote Device ID': remoteId,
        'Transfer ID': transferId,
        'Connection Types': connectionTypes,
        if (receiveError != null) ...errorProps(receiveError),
        if (sender != null) ...remoteDeviceProperties(sender),
        if (receivePayload != null)
          ...await payloadProperties([receivePayload]),
      });
    }
  }

  Future<List<String>> getConnectionTypes(RTCPeerConnection connection) async {
    List<StatsReport> stats;
    try {
      // On windows, getStats currently never gives a result
      // https://github.com/flutter-webrtc/flutter-webrtc/issues/904
      stats = await connection.getStats().timeout(const Duration(seconds: 1));
    } catch (error) {
      logger("STATS: Could not get connection types used");
      return [];
    }
    var pairs =
        stats.where((element) => element.type == 'googCandidatePair').toList();
    var usedPairs =
        pairs.where((it) => int.parse(it.values['bytesSent']) > 0).toList();
    return usedPairs
        .map((it) => it.values['googRemoteCandidateType'].toString())
        .toList();
  }

  Future observe(
      Function(Payload? payload, Object? error, String message)
          callback) async {
    await signaling.observe(localDevice, (message, remoteId) async {
      Map<String, dynamic> json = jsonDecode(message);
      String type = json['type'];
      String transferId = json['transferId'];
      int remoteVersion = json['version'] ?? 0;
      Map<String, dynamic> payload = json['payload'];
      Map<String, dynamic>? senderData = json['sender'];
      if (senderData != null) {
        var device = Device.decode(senderData);
        if (device.id != localDevice.id) {
          saveDeviceInfo(device);
        }
      }

      int localVersion = MessageSender.communicationVersion;

      if (type == 'localPing') {
        logger('PING: Local ping received');
        return;
      }

      if (type == 'ping') {
        logger('PING: Received');
        var messageSender =
            MessageSender(localDevice, remoteId, transferId, signaling);
        await messageSender.sendMessage('pingResponse', {});

        // This is for receiver, sender is handled as an AppException
        if (remoteVersion != localVersion) {
          callback(null, null,
              'Transfer failed. Update to the latest app version on both the sending and receiving devices.');
          ErrorLogger.logSimpleError('receiverVersionMismatch',
              {'local': localVersion, 'remote': remoteVersion});
        }
        return;
      }

      if (type == 'offer') {
        // The || activeTransferId == transferId is tmp to support sender and receiver same device
        if (activeTransferId == null || activeTransferId == transferId) {
          await receiveFile(
              localDevice.id, remoteId, transferId, payload, callback);
        } else {
          logger(
              "Transfer already in progress $activeTransferId. Attempted $transferId");
        }
      } else {
        if (activeTransferId == transferId) {
          observer.handleMessage(type, remoteVersion, payload);
        } else {
          logger(
              "Message '$type' with incorrect transfer id ignored $transferId != $activeTransferId");
        }
      }
    });
  }

  startPing() {
    Timer.periodic(const Duration(seconds: 60),
        (timer) => sendPing(signaling, localDevice));
    sendPing(signaling, localDevice);
  }

  Future<Map<String, dynamic>> getIceServerConfig() async {
    var prefs = await SharedPreferences.getInstance();
    String? appInfoJson = prefs.getString('appInfo');
    if (appInfoJson != null) {
      Map<String, dynamic> appInfo = jsonDecode(appInfoJson);
      var config = appInfo['connectionConfig'];
      String provider = config['provider'];
      List<dynamic> iceServers = jsonDecode(config['iceServers']);
      return {
        //'iceTransportPolicy': 'relay',
        'provider': provider,
        'iceServers': iceServers,
      };
    } else {
      ErrorLogger.logSimpleError('stunConfigUsed');
      return <String, dynamic>{
        "provider": "google",
        'iceServers': [
          {'url': 'stun:stun.l.google.com:19302'},
        ],
      };
    }
  }
}

class SignalingObserver {
  String localId;
  Signaling signaling;

  Function(Map<String, dynamic> candidate)? onSenderIceCandidate;
  Function(Map<String, dynamic> candidate)? onReceiverIceCandidate;
  Function(Map<String, dynamic> answer)? onAnswer;
  Function(int version)? onPingResponse;

  SignalingObserver(this.localId, this.signaling);

  handleMessage(String type, int remoteVersion, Map<String, dynamic> payload) {
    if (type == 'senderIceCandidate') {
      if (onSenderIceCandidate != null) {
        onSenderIceCandidate!(payload);
      } else {
        logger("No listener for $type");
      }
    } else if (type == 'receiverIceCandidate') {
      if (onReceiverIceCandidate != null) {
        onReceiverIceCandidate!(payload);
      } else {
        logger("No listener for $type");
      }
    } else if (type == 'answer') {
      if (onAnswer != null) {
        onAnswer!(payload);
      } else {
        logger("No listener for $type");
      }
    } else if (type == 'pingResponse') {
      if (onPingResponse != null) {
        onPingResponse!(remoteVersion);
      }
    } else {
      ErrorLogger.logSimpleError('invalidMessageType', {'type': type});
    }
  }
}

class MessageSender {
  static var communicationVersion = 4;

  Signaling signaling;
  Device sender;
  String remoteId;
  String transferId;

  MessageSender(this.sender, this.remoteId, this.transferId, this.signaling);

  sendMessage(String type, Map<String, dynamic> payload) async {
    var json = jsonEncode({
      'version': communicationVersion,
      'transferId': transferId,
      'type': type,
      'payload': payload,
      'sender': sender.encode(),
    });
    return await signaling.sendMessage(sender.id, remoteId, json);
  }
}
