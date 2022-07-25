import 'dart:convert';
import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:http/http.dart' as http;

import 'tools_config.dart';

class PlayStoreSubmitter {
  var baseUrl =
      'https://androidpublisher.googleapis.com/androidpublisher/v3/applications/io.flown.airdash';

  play() async {
    var editId = await createEdit();
    print(editId);
    var res = await send('POST', '/edits/$editId:commit');
    print(res);
  }

  Future<String> createEdit() async {
    var edit = await send('POST', '/edits');
    return edit['id'];
  }

  Future<Map<String, dynamic>> send(String method, String path,
      {Map<String, dynamic>? requestBody}) async {
    print('$method $baseUrl$path');
    var uri = Uri.parse('$baseUrl$path');

    var token = await _generateToken();

    var req = http.Request(method, uri);
    req.headers.addAll({
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    });
    if (requestBody != null) req.body = jsonEncode(requestBody);

    var res = await req.send();
    var body = await res.stream.bytesToString();
    if (res.statusCode < 200 || res.statusCode >= 300) {
      print(body);
      throw Exception('Invalid status code ${res.statusCode}');
    }

    return body.isNotEmpty ? jsonDecode(body) : {'success': true};
  }

  Future<String> _generateToken() async {
    var serviceAccountJson = File(Config.googlePlayKeyPath).readAsStringSync();
    Map serviceAccount = jsonDecode(serviceAccountJson);

    String email = serviceAccount['client_email'];
    String tokenUri = serviceAccount['token_uri'];
    String privateKey = serviceAccount['private_key'];

    int creationTime = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final jwt = JWT(
      {
        "iat": creationTime,
        "exp": creationTime + 3000,
        "iss": email,
        "scope": 'https://www.googleapis.com/auth/androidpublisher',
        "aud": tokenUri,
      },
      header: {
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
    var resBody = jsonDecode(res.body);
    String accessToken = resBody['access_token'];

    return accessToken;
  }
}
