import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'command_runner.dart';
import 'tools_config.dart';
import 'version_editor.dart';

class MicrosoftStoreSubmitter {
  var api = MicrosoftPartnerCenterApi();
  var applicationId = Config.windowsApiAppId;

  submit() async {
    var status = await getAppStatus();
    if (status['pendingApplicationSubmission'] != null) {
      var submissionId = status['pendingApplicationSubmission']['id'];
      await deleteSubmission(submissionId);
    }

    // Got InvalidState error for addSubmission. Worth exploring further?
    // When it happened the deleteSubmission call was not called above.
    var submission = await addSubmission();
    var submissionId = submission['id'];

    var currentVersion = VersionEditor().readCurrentVersion();
    await uploadPackage(
        submissionId, submission['fileUploadUrl'], currentVersion);
    await updateSubmissionPackages(submission, currentVersion);

    await submitSubmission(submissionId);
    await waitForProcessing(submissionId);

    print('Submission finished');
  }

  getAppStatus() {
    return api.send('GET', '/my/applications/$applicationId');
  }

  deleteSubmission(String submissionId) async {
    var path = '/my/applications/$applicationId/submissions/$submissionId';
    await api.send('DELETE', path);
  }

  addSubmission() async {
    var path = '/my/applications/$applicationId/submissions';
    return api.send('POST', path);
  }

  waitForProcessing(String submissionId) async {
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
      await Future.delayed(const Duration(seconds: 5));
    }
  }

  getSubmissionStatus(String submissionId) async {
    var path =
        '/my/applications/$applicationId/submissions/$submissionId/status';
    return api.send('GET', path);
  }

  getCurrentSubmissionStatus() async {
    var status = await getAppStatus();
    var submissionId = status['pendingApplicationSubmission']['id'];
    return getSubmissionStatus(submissionId);
  }

  getSubmission(String submissionId) async {
    var path = '/my/applications/$applicationId/submissions/$submissionId';
    return api.send('GET', path);
  }

  submitSubmission(String submissionId) async {
    var path =
        '/my/applications/$applicationId/submissions/$submissionId/commit';
    await api.send('POST', path);
  }

  updateSubmissionPackages(Map submission, List<int> version) async {
    var path =
        '/my/applications/$applicationId/submissions/${submission['id']}';
    List applicationPackages = submission['applicationPackages'] ?? [];
    for (var package in applicationPackages) {
      package['fileStatus'] = 'PendingDelete';
    }
    applicationPackages.add({
      'fileName': 'AirDash.msix',
      'version': '${version.join('.')}.0',
    });
    return api.send('PUT', path, body: jsonEncode(submission));
  }

  uploadPackage(String submissionId, String url, List<int> version) async {
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

  send(String method, String path, {String? body}) async {
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
        return jsonDecode(resBody);
      } catch (error) {
        print(resBody);
        print('Could not parse json');
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

    String accessToken = jsonDecode(result.body)['access_token'];
    print('Got access token: ${accessToken.substring(0, 10)}...');

    return accessToken;
  }
}
