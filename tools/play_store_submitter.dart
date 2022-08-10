import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import 'tools_config.dart';

class PlayStoreSubmitter {
  var uploadBaseUrl =
      'https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/io.flown.airdash';
  var baseUrl =
      'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/io.flown.airdash';

  Future play() async {
    var editId = await createEdit();
    print(editId);
    var res = await send('GET', '/edits/$editId/tracks');
    print(res);
  }

  Future<String> createEdit() async {
    var edit = await send('POST', '/edits');
    return edit['id'] as String;
  }

  Future<dynamic> commitEdit(String editId) async {
    return send('POST', '/edits/$editId:commit');
  }

  Future uploadBundle(String editId) async {
    var bytes = File('build/app-release.aab').readAsBytesSync();
    print(bytes.take(10));
    var res = await send(
      'POST',
      '/edits/$editId/bundles',
      requestBody: bytes,
      fileUpload: true,
    );
    print(res);
  }

  Future<Map<String, dynamic>> send(String method, String path,
      {dynamic requestBody,
      Map<String, String>? headers,
      bool fileUpload = false}) async {
    var base = baseUrl;
    if (fileUpload) {
      base = uploadBaseUrl;
    }
    print('$method $base$path');
    var uri = Uri.parse('$base$path');

    var token = await _generateToken();

    var req = http.Request(method, uri);
    req.headers.addAll({
      'Content-Type': 'application/${fileUpload ? 'octet-stream' : 'json'}',
      'Authorization': 'Bearer $token',
    });
    if (headers != null) req.headers.addAll(headers);

    if (requestBody is List<int>) req.bodyBytes = requestBody;
    if (requestBody is String) req.body = requestBody;

    var res = await req.send();
    var body = await res.stream.bytesToString();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      print(body);
      throw Exception('Invalid status code ${res.statusCode}');
    }

    return body.isNotEmpty
        ? jsonDecode(body) as Map<String, dynamic>
        : <String, dynamic>{'success': true};
  }

  Future<String> _generateToken() async {
    var serviceAccountJson = File(Config.googlePlayKeyPath).readAsStringSync();
    var serviceAccount = jsonDecode(serviceAccountJson) as Map;

    var email = serviceAccount['client_email'] as String;
    var tokenUri = serviceAccount['token_uri'] as String;
    var privateKey = serviceAccount['private_key'] as String;

    int creationTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final jwt = JWT(
      {
        "iat": creationTime,
        "exp": creationTime + 3000,
        "iss": email,
        "scope": 'https://www.googleapis.com/auth/androidpublisher',
        "aud": tokenUri,
      },
      header: <String, String>{
        "alg": "RS256",
        "typ": "JWT",
      },
    );

    final jwtToken =
        jwt.sign(RSAPrivateKey(privateKey), algorithm: JWTAlgorithm.RS256);

    var json = {
      'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      'assertion': jwtToken,
    };

    var uri = Uri.parse('https://oauth2.googleapis.com/token');
    var res = await http.post(uri, body: jsonEncode(json));
    var resBody = jsonDecode(res.body) as Map;
    var accessToken = resBody['access_token'] as String;

    return accessToken;
  }
}
