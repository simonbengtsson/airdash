import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simple_peer/simple_peer.dart';
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
    'mandatory': <String, String>{},
    'optional': [
      {'DtlsSrtpKeyAgreement': true},
    ],
  };

  Device localDevice;
  Signaling signaling;

  String? activeTransferId;
  Function(SignalingInfo)? signal;

  RTCDataChannelInit get dcConfig {
    var dcConfig = RTCDataChannelInit();
    dcConfig.negotiated = true;
    dcConfig.id = 1001;
    return dcConfig;
  }

  Connector(this.localDevice, this.signaling);

  static Connector create(Device localDevice, Peer peer) {
    var signaling = Signaling();
    return Connector(localDevice, signaling);
  }

  Function(int)? onPingResponse;

  Future sendFile(Device receiver, List<Payload> payloads,
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
      await communicatorChannel
          .invokeMethod<void>('startFileSending', <String, dynamic>{});
    }
    logger('SENDER: Started background task');

    DataSender? sender;
    Object? sendError;
    var transferId = generateId(28);
    activeTransferId = transferId;

    var payloadProps = await payloadProperties(payloads);
    AnalyticsEvent.sendingStarted.log(<String, dynamic>{
      'Transfer ID': transferId,
      ...remoteDeviceProperties(receiver),
      ...payloadProps,
    });
    try {
      await Wakelock.enable();
      logger('SENDER: Start transfer $transferId');

      var config = await getIceServerConfig();
      var peer = await Peer.create(
          initiator: true,
          config: config,
          dataChannelConfig: dcConfig,
          verbose: true);
      signal = peer.signal;

      var messageSender =
          MessageSender(localDevice, receiver.id, transferId, signaling);
      peer.onSignal = (info) {
        var payload = info.payload as Map<String, dynamic>;
        messageSender.sendMessage(info.type, payload);
      };
      sender = await DataSender.create(peer, file, meta);
      await googlePing();
      var completer = SingleCompleter<String>();
      messageSender.sendMessage('ping', <String, dynamic>{});
      onPingResponse = (remoteVersion) {
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
      logger('SENDER: Device ping completed');
      await sender.connect();
      logger('SENDER: Connection established');
      await sender.sendFile(statusCallback);
    } catch (error) {
      sendError = error;
      rethrow;
    } finally {
      await Wakelock.disable();
      List<String> connectionTypes = [];
      if (sender != null) {
        connectionTypes = await getConnectionTypes(sender.peer.connection);
        logger('SENDER: Finished with $connectionTypes');
        await sender.peer.connection.close();
        await sender.senderState.raFile.close();
      }
      activeTransferId = null;
      signaling.receivedMessages = <String, dynamic>{};
      if (Platform.isIOS) {
        await communicatorChannel
            .invokeMethod<void>('endFileSending', <String, dynamic>{});
      }
      logger('SENDER: Connector cleaned up');

      AnalyticsEvent.sendingCompleted.log(<String, dynamic>{
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

  Future saveDeviceInfo(Device device) async {
    var prefs = await SharedPreferences.getInstance();
    var list = prefs.getStringList('receivers') ?? [];
    var devices = list
        .map((r) => Device.decode(jsonDecode(r) as Map<String, dynamic>))
        .toList();
    devices.removeWhere((element) => element.id == device.id);
    devices.add(device);
    await prefs.setStringList(
        'receivers', devices.map((r) => jsonEncode(r.encode())).toList());
  }

  Future googlePing() async {
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

  Future receiveFile(
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
    var devices = list
        .map((r) => Device.decode(jsonDecode(r) as Map<String, dynamic>))
        .toList();
    var sender = devices.where((element) => element.id == remoteId).firstOrNull;

    if (sender == null) {
      ErrorLogger.logSimpleError('Receiving file from unknown sender');
    }

    AnalyticsEvent.receivingStarted.log(<String, dynamic>{
      'Transfer ID': transferId,
      if (sender != null) ...remoteDeviceProperties(sender),
    });

    Payload? receivePayload;
    Object? receiveError;
    Receiver? receiver;
    try {
      var config = await getIceServerConfig();
      var peer = await Peer.create(
          config: config, dataChannelConfig: dcConfig, verbose: true);
      signal = peer.signal;
      await Wakelock.enable();
      var messageSender =
          MessageSender(localDevice, remoteId, transferId, signaling);
      peer.onSignal = (info) {
        messageSender.sendMessage(
            info.type, info.payload as Map<String, dynamic>);
      };
      var receiver = await Receiver.create(peer);
      await peer.signal(SignalingInfo('offer', offer));
      await receiver.connect();
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
        connectionTypes = await getConnectionTypes(receiver.peer.connection);
        logger('RECEIVER: Finished with $connectionTypes');
      }
      await Wakelock.disable();
      await receiver?.peer.connection.close();
      activeTransferId = null;
      signaling.receivedMessages = <String, dynamic>{};
      logger('RECEIVER: Receiver cleanup finished');

      AnalyticsEvent.receivingCompleted.log(<String, dynamic>{
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
    var usedPairs = pairs
        .where((it) => int.parse(it.values['bytesSent'] as String) > 0)
        .toList();
    return usedPairs
        .map((it) => it.values['googRemoteCandidateType'].toString())
        .toList();
  }

  Future observe(
      Function(Payload? payload, Object? error, String message)
          callback) async {
    await signaling.observe(localDevice, (message, remoteId) async {
      var json = jsonDecode(message) as Map<String, dynamic>;
      var type = json['type'] as String;
      var transferId = json['transferId'] as String;
      int remoteVersion = json['version'] as int? ?? 0;
      var payload = json['payload'] as Map<String, dynamic>;
      var senderData = json['sender'] as Map<String, dynamic>?;
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
        await messageSender.sendMessage('pingResponse', <String, dynamic>{});

        // This is for receiver, sender is handled as an AppException
        if (remoteVersion != localVersion) {
          callback(null, null,
              'Transfer failed. Update to the latest app version on both the sending and receiving devices.');
          ErrorLogger.logSimpleError(
              'receiverVersionMismatch', <String, dynamic>{
            'local': localVersion,
            'remote': remoteVersion
          });
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
          if (type == 'pingResponse') {
            onPingResponse!(remoteVersion);
          } else if ([
            'senderIceCandidate',
            'receiverIceCandidate',
            'answer',
          ].contains(type)) {
            signal!(SignalingInfo(type, payload));
          } else {
            ErrorLogger.logSimpleError(
                'invalidMessageType', <String, dynamic>{'type': type});
          }
        } else {
          logger(
              "Message '$type' with incorrect transfer id ignored $transferId != $activeTransferId");
        }
      }
    });
  }

  void startPing() {
    Timer.periodic(const Duration(seconds: 60),
        (timer) => sendPing(signaling, localDevice));
    sendPing(signaling, localDevice);
  }

  Future<Map<String, dynamic>> getIceServerConfig() async {
    var prefs = await SharedPreferences.getInstance();
    String? appInfoJson = prefs.getString('appInfo');
    if (appInfoJson != null) {
      var appInfo = jsonDecode(appInfoJson) as Map<String, dynamic>;
      var config = appInfo['connectionConfig'] as Map;
      var provider = config['provider'] as String;
      var iceServers = jsonDecode(config['iceServers'] as String) as List;
      return <String, dynamic>{
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

class MessageSender {
  static var communicationVersion = 4;

  Signaling signaling;
  Device sender;
  String remoteId;
  String transferId;

  MessageSender(this.sender, this.remoteId, this.transferId, this.signaling);

  Future sendMessage(String type, Map<String, dynamic> payload) async {
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
