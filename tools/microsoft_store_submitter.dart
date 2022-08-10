import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'command_runner.dart';
import 'tools_config.dart';
import 'version_editor.dart';

class MicrosoftStoreSubmitter {
  var api = MicrosoftPartnerCenterApi();
  var applicationId = Config.windowsApiAppId;

  Future submit() async {
    var status = await getAppStatus();
    if (status['pendingApplicationSubmission'] != null) {
      var submissionId = status['pendingApplicationSubmission']['id'] as String;
      await deleteSubmission(submissionId);
    }

    // Got InvalidState error for addSubmission. Worth exploring further?
    // When it happened the deleteSubmission call was not called above.
    var submission = await addSubmission();
    var submissionId = submission['id'] as String;

    var currentVersion = VersionEditor().readCurrentVersion();
    await uploadPackage(
        submissionId, submission['fileUploadUrl'] as String, currentVersion);
    await updateSubmissionPackages(submission, currentVersion);

    await submitSubmission(submissionId);
    await waitForProcessing(submissionId);

    print('Submission finished');
  }

  Future<Map> getAppStatus() async {
    var map = await api.send('GET', '/my/applications/$applicationId');
    return map!;
  }

  Future deleteSubmission(String submissionId) async {
    var path = '/my/applications/$applicationId/submissions/$submissionId';
    await api.send('DELETE', path);
  }

  Future<Map> addSubmission() async {
    var path = '/my/applications/$applicationId/submissions';
    var res = await api.send('POST', path);
    return res as Map;
  }

  Future waitForProcessing(String submissionId) async {
    while (true) {
      var status = await getSubmissionStatus(submissionId);
      if (!['PreProcessing', 'CommitStarted'].contains(status['status'])) {
        print('Finished commit. New status is ${status['status']}');
        if (status['status'] == 'CommitFailed') {
          print(formatJson(status));
          throw Exception('Submission failed');
        }
        break;
      }
      print('Waiting, still ${status['status']}');
      await Future<void>.delayed(const Duration(seconds: 5));
    }
  }

  Future<Map> getSubmissionStatus(String submissionId) async {
    var path =
        '/my/applications/$applicationId/submissions/$submissionId/status';
    var res = await api.send('GET', path);
    return res!;
  }

  Future<Map> getCurrentSubmissionStatus() async {
    var status = await getAppStatus();
    var submissionId = status['pendingApplicationSubmission']['id'] as String;
    return getSubmissionStatus(submissionId);
  }

  Future getSubmission(String submissionId) async {
    var path = '/my/applications/$applicationId/submissions/$submissionId';
    return api.send('GET', path);
  }

  Future submitSubmission(String submissionId) async {
    var path =
        '/my/applications/$applicationId/submissions/$submissionId/commit';
    await api.send('POST', path);
  }

  Future updateSubmissionPackages(Map submission, List<int> version) async {
    var path =
        '/my/applications/$applicationId/submissions/${submission['id']}';
    var packages = submission['applicationPackages'] as Iterable?;
    var applicationPackages = List<Map>.from(packages ?? <Map>[]);
    for (var package in applicationPackages) {
      package['fileStatus'] = 'PendingDelete';
    }
    applicationPackages.add(<String, String>{
      'fileName': 'AirDash.msix',
      'version': '${version.join('.')}.0',
    });
    return api.send('PUT', path, body: jsonEncode(submission));
  }

  Future uploadPackage(
      String submissionId, String url, List<int> version) async {
    var zipFile = File('build/upload.zip');
    runLocalCommand(
        'zip ${zipFile.path} ${Config.localRepoPath}/build/AirDash.msix -j');
    var msixBytes = await zipFile.readAsBytes();

    var headers = {
      "x-ms-blob-type": "BlockBlob",
      'Content-Type': 'application/json'
    };
    print('Uploading msix package...');
    var res = await http.put(Uri.parse(url), headers: headers, body: msixBytes);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      print('Ok ${res.statusCode}');
    } else {
      print(res.body);
      print('Status code ${res.statusCode}');
      throw Exception('Error calling api');
    }
  }
}

class MicrosoftPartnerCenterApi {
  var baseUrl = 'https://manage.devcenter.microsoft.com/v1.0';

  Future<Map?> send(String method, String path, {String? body}) async {
    print('$method $path');

    var url = Uri.parse('$baseUrl$path');
    var accessToken = await _getAccessToken();

    var headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
    };

    var req = http.Request(method, url)..headers.addAll(headers);
    if (body != null) req.body = body;

    var res = await req.send();
    final resBody = await res.stream.bytesToString();

    if (res.statusCode >= 200 && res.statusCode < 300) {
      try {
        return jsonDecode(resBody) as Map;
      } catch (error) {
        print(resBody);
        print('Could not parse json');
        return null;
      }
    } else {
      print(resBody);
      print('Status code ${res.statusCode}');
      throw Exception('Error calling api');
    }
  }

  Future<String> _getAccessToken() async {
    var encodedClientSecret = Uri.encodeFull(Config.windowsApiClientSecret);
    var body = [
      'grant_type=client_credentials',
      'client_id=${Config.windowsApiClientId}',
      'client_secret=$encodedClientSecret',
      'resource=https://manage.devcenter.microsoft.com'
    ].join('&');
    var url =
        'https://login.microsoftonline.com/${Config.windowsApiTenantId}/oauth2/token';
    var headers = {
      'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
    };
    var result = await http.post(Uri.parse(url), headers: headers, body: body);

    if (result.statusCode != 200) {
      print(result.body);
      print('Status code: ${result.statusCode}');
      throw Exception('Could not get access token');
    }

    var accessToken = jsonDecode(result.body)['access_token'] as String;
    print('Got access token: ${accessToken.substring(0, 10)}...');

    return accessToken;
  }
}
