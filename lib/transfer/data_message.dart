import 'dart:convert';

import 'package:flutter_webrtc/flutter_webrtc.dart';

class Message {
  RTCDataChannelMessage rtcMessage;
  Map<String, dynamic> header;
  List<int> chunk;
  int lengthInBytes;

  Map<String, String> get meta {
    var meta = header['meta'];
    if (meta != null) {
      return Map<String, String>.from(meta);
    } else {
      return {};
    }
  }

  int get version {
    return header['version'] as int;
  }

  String get filename {
    return header['filename'] as String;
  }

  int get fileSize {
    return header['fileSize'] as int;
  }

  int get messageSize {
    return header['messageSize'] as int;
  }

  int get chunkStart {
    return header['chunkStart'] as int;
  }

  Message(this.rtcMessage, this.chunk, this.header, this.lengthInBytes);

  static Message parse(RTCDataChannelMessage rtcMessage) {
    List<int> binary = rtcMessage.isBinary
        ? rtcMessage.binary
        : base64.decode(rtcMessage.text);

    var isFileContent = false;
    List<int> chunk = [];
    List<int> headerBytes = [];
    for (var byte in binary) {
      if (isFileContent) {
        chunk.add(byte);
      } else if (byte == '\n'.codeUnitAt(0)) {
        isFileContent = true;
      } else {
        headerBytes.add(byte);
      }
    }

    var json = utf8.decode(headerBytes);
    Map<String, dynamic> header = jsonDecode(json);

    return Message(rtcMessage, chunk, header, binary.length);
  }
}
