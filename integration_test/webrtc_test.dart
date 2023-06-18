import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:integration_test/integration_test.dart';

final loopbackConstraints = <String, dynamic>{
  'mandatory': <String, String>{},
  'optional': [
    {'DtlsSrtpKeyAgreement': true},
  ],
};

var activeConfig = <String, dynamic>{
  "provider": "google",
  'iceServers': [
    {'url': 'stun:stun.l.google.com:19302'},
  ],
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('test local ice gathering', (tester) async {
    var completer = Completer<bool>();
    completer.future.timeout(const Duration(seconds: 2));

    var local = await createPeerConnection(activeConfig, loopbackConstraints);
    local.onIceCandidate = (event) {
      var type = event.candidate?.split(' ')[7];
      print("New ice with type: $type");
      completer.complete(true);
      local.close();
    };

    await local.createDataChannel('sendChannel', RTCDataChannelInit());
    var offer = await local.createOffer();
    await local.setLocalDescription(offer);
    await completer.future;
  });

  // Will currently fail on windows https://github.com/flutter-webrtc/flutter-webrtc/issues/904
  testWidgets('test getStats call', (tester) async {
    var pc = await createPeerConnection(<String, String>{});
    await pc.getStats().timeout(const Duration(seconds: 10));
  });

  testWidgets('test auto negotiated connection', (tester) async {
    var tester = AutoNegotiatedTester();
    await tester.testConnection();
  });

  testWidgets('test manually negotiated connection', (tester) async {
    var tester = ManuallyNegotiatedChannel();
    await tester.testConnection();
  });
}

class AutoNegotiatedTester {
  RTCPeerConnection? local;
  RTCPeerConnection? remote;

  Future<void> testConnection() async {
    local = await createPeerConnection(activeConfig, loopbackConstraints);
    print('Created local connection');
    var dcInit = RTCDataChannelInit();
    var localChannel = await local!.createDataChannel('sendChannel', dcInit);
    print('Created local data channel');

    List<RTCIceCandidate> localIceCandidates = [];
    local!.onIceCandidate = (candidate) {
      var type = candidate.candidate?.split(' ')[7];
      print("Local ice: $type");
      localIceCandidates.add(candidate);
    };

    remote = await createPeerConnection(activeConfig, loopbackConstraints);

    List<RTCIceCandidate> remoteIceCandidates = [];
    remote!.onIceCandidate = (candidate) {
      var type = candidate.candidate?.split(' ')[7];
      print("Remote ice: $type");
      remoteIceCandidates.add(candidate);
    };

    var offer = await local!.createOffer();
    await local!.setLocalDescription(offer);
    await remote!.setRemoteDescription(offer);

    var answer = await remote!.createAnswer();
    print('Created answer');

    await remote!.setLocalDescription(answer);
    print('Set answer on remote');

    await local!.setRemoteDescription(answer);
    print('Set answer on local');

    localChannel.onDataChannelState = (state) async {
      print('Local channel state $state');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        await Future<dynamic>.delayed(const Duration(seconds: 1));
        var message = RTCDataChannelMessage('Hello from local!');
        await localChannel.send(message);
        print('Sent local message');
      }
    };

    print('Waiting for all ice candidates...');
    await Future<dynamic>.delayed(const Duration(seconds: 2));

    assert(remoteIceCandidates.isNotEmpty, 'Has remote ice candidates');
    assert(localIceCandidates.isNotEmpty, 'Has local ice candidates');

    for (var it in remoteIceCandidates) {
      local!.addCandidate(it);
    }
    for (var it in localIceCandidates) {
      remote!.addCandidate(it);
    }
    print('Added ice candidates');

    var completer = Completer<String>();
    localChannel.onMessage = (message) {
      print('Local channel message: ${message.text}');
      assert(true, 'Got remote reply message');
      completer.complete('done');
    };
    remote!.onDataChannel = (channel) async {
      print(
          'Data channel received. ${channel.state.toString()} Remote id: ${channel.id}. Local id: ${localChannel.id}');
      var reply1 = RTCDataChannelMessage('Hello from remote!');
      await channel.send(reply1);
      print('Sent initial reply');

      channel.onMessage = (message) async {
        print('Remote channel message: ${message.text}');
        assert(true, 'Got local message');
        print('Channel state: ${channel.state.toString()}');
        var reply = RTCDataChannelMessage('Hello from remote!');
        await channel.send(reply);
        print('Sent reply');
      };
    };
    await completer.future.timeout(const Duration(seconds: 5));
    remote!.close();
    local!.close();
    await Future<void>.delayed(const Duration(seconds: 2));
    print('Done');
  }
}

class ManuallyNegotiatedChannel {
  RTCPeerConnection? local;
  RTCPeerConnection? remote;

  Future<void> testConnection() async {
    local = await createPeerConnection(activeConfig, loopbackConstraints);
    print('Created local connection');
    var dcInit = RTCDataChannelInit();
    dcInit.negotiated = true;
    dcInit.id = 1000;
    var localChannel = await local!.createDataChannel('sendChannel', dcInit);
    print('Created local data channel');

    local!.onRenegotiationNeeded = () {
      print('Local: onRenegotiationNeeded');
    };
    local!.onConnectionState = (state) {
      print('Local connection state ${state.name}');
    };
    List<RTCIceCandidate> localIceCandidates = [];
    local!.onIceCandidate = (candidate) {
      var type = candidate.candidate?.split(' ')[7];
      print("Local ice: $type");
      localIceCandidates.add(candidate);
    };

    remote = await createPeerConnection(activeConfig, loopbackConstraints);

    var dcInit2 = RTCDataChannelInit();
    dcInit2.negotiated = true;
    dcInit2.id = 1000;
    var remoteChannel = await remote!.createDataChannel('sendChannel', dcInit2);
    print('Created local data channel');

    remote!.onConnectionState = (state) {
      print('Remote connection state ${state.name}');
    };
    remote!.onIceGatheringState = (state) {};
    remote!.onIceConnectionState = (state) {};
    remote!.onRenegotiationNeeded = () {
      print('Remote onRenegotiationNeeded');
    };
    List<RTCIceCandidate> remoteIceCandidates = [];
    remote!.onIceCandidate = (candidate) {
      var type = candidate.candidate?.split(' ')[7];
      print("Remote ice: $type");
      remoteIceCandidates.add(candidate);
    };
    print('Create remote connection');

    var offer = await local!.createOffer();
    print('Created offer');

    await local!.setLocalDescription(offer);
    print('Set offer locally');

    await remote!.setRemoteDescription(offer);
    print('Set offer remotely');

    var answer = await remote!.createAnswer();
    print('Created answer');

    await remote!.setLocalDescription(answer);
    print('Set answer on remote');

    await local!.setRemoteDescription(answer);
    print('Set answer on local');

    remoteChannel.onDataChannelState = (state) async {
      print('Remote channel state $state');
    };

    localChannel.onDataChannelState = (state) async {
      print('Local channel state $state');
      if (state == RTCDataChannelState.RTCDataChannelOpen) {
        await Future<void>.delayed(const Duration(seconds: 1));
        var message = RTCDataChannelMessage('Hello from local!');
        await localChannel.send(message);
        print('Sent local message');
      }
    };

    print('Waiting for all ice candidates...');
    await Future<void>.delayed(const Duration(seconds: 2));

    for (var it in remoteIceCandidates) {
      local!.addCandidate(it);
    }
    for (var it in localIceCandidates) {
      remote!.addCandidate(it);
    }
    print('Added ice candidates');

    var completer = Completer<bool>();
    localChannel.onMessage = (message) {
      print('Got reply: ${message.text}');
      completer.complete(true);
    };

    remoteChannel.onMessage = (message) async {
      print(
          'Remote channel message: ${message.text} ${remoteChannel.state.toString()}');
      var reply = RTCDataChannelMessage('Hello from remote!');
      await remoteChannel.send(reply);
      print('Sent reply');
    };
    await completer.future;
    remote!.close();
    local!.close();
    await Future<void>.delayed(const Duration(seconds: 2));
    print('Done');
  }
}
