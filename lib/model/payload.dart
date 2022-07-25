import 'dart:io';

abstract class Payload {}

class FilePayload extends Payload {
  File file;

  String get filename {
    return file.uri.pathSegments.last;
  }

  FilePayload(this.file);
}

class UrlPayload extends Payload {
  Uri httpUrl;

  UrlPayload(this.httpUrl);
}
