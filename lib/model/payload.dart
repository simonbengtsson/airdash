import 'dart:io';

abstract class Payload {}

class IPayload {
  String? httpUrl;
}

class FilePayload extends Payload {
  List<File> files = [];

  FilePayload(this.files);
}

class UrlPayload extends Payload {
  Uri httpUrl;

  UrlPayload(this.httpUrl);
}
