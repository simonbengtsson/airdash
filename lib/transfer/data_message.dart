import 'dart:convert';

class Message {
  Map<String, dynamic> header;
  List<int> chunk;
  int lengthInBytes;

  Map<String, String> get meta {
    return Map<String, String>.from(
        header['meta'] as Map? ?? <String, dynamic>{});
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

  Message(this.chunk, this.header, this.lengthInBytes);

  static Message parse(List<int> bytes) {
    var isFileContent = false;
    List<int> chunk = [];
    List<int> headerBytes = [];
    for (var byte in bytes) {
      if (isFileContent) {
        chunk.add(byte);
      } else if (byte == '\n'.codeUnitAt(0)) {
        isFileContent = true;
      } else {
        headerBytes.add(byte);
      }
    }

    var json = utf8.decode(headerBytes);
    var header = jsonDecode(json) as Map<String, dynamic>;

    return Message(chunk, header, bytes.length);
  }
}
