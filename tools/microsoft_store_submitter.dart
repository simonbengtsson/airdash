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

  getAppStatus() async {
    var map = await api.send('GET', '/my/applications/$applicationId');
    return map;
  }

  deleteSubmission(String submissionId) async {
    var path = '/my/applications/$applicationId/submissions/$submissionId';
    await api.send('DELETE', path);
  }

  Future<Map<String, dynamic>> addSubmission() async {
    var path = '/my/applications/$applicationId/submissions';
    var res = await api.send('POST', path);
    return res;
  }

  waitForProcessing(String submissionId) async {
    var startedAt = DateTime.now();
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
    var endedAt = DateTime.now();
    print(
        'Done! Took ${(endedAt.difference(startedAt).inSeconds / 60).toStringAsFixed(1)} min');
  }

  Future<Map<String, dynamic>> getSubmissionStatus(String submissionId) async {
    var path =
        '/my/applications/$applicationId/submissions/$submissionId/status';
    var res = await api.send('GET', path);
    return res;
  }

  Future<Map<String, dynamic>> getCurrentSubmissionStatus() async {
    var status = await getAppStatus();
    var submissionId = status['pendingApplicationSubmission']['id'] as String;
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

  updateSubmissionPackages(
      Map<String, dynamic> submission, List<int> version) async {
    var path =
        '/my/applications/$applicationId/submissions/${submission['id']}';
    var packages = submission['applicationPackages'] as Iterable?;
    var applicationPackages =
        List<Map<String, dynamic>>.from(packages ?? <Map<String, dynamic>>[]);
    for (var package in applicationPackages) {
      package['fileStatus'] = 'PendingDelete';
    }
    applicationPackages.add(<String, String>{
      'fileName': 'AirDash.msix',
      'fileStatus': 'PendingUpload',
      'version': '${version.join('.')}.0',
    });
    submission['applicationPackages'] = applicationPackages;
    return api.send('PUT', path, body: jsonEncode(submission));
  }

  Future<void> uploadPackage(
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

  Future<Map<String, dynamic>> send(String method, String path,
      {String? body, int retries = 3}) async {
    var url = Uri.parse('$baseUrl$path');
    var accessToken = await _getAccessToken();
    print('$method $path ${accessToken.substring(0, 10)}...');

    var headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $accessToken',
    };

    var req = http.Request(method, url)..headers.addAll(headers);
    if (body != null) req.body = body;

    var res = await req.send();
    final resBody = await res.stream.bytesToString();

    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (resBody.isNotEmpty) {
        return jsonDecode(resBody) as Map<String, dynamic>;
      } else {
        return {};
      }
    } else {
      print(resBody);
      print('Status code ${res.statusCode}');

      if (res.statusCode == 500 && retries > 0) {
        print('Retrying... Retries left: $retries');
        await Future<void>.delayed(const Duration(seconds: 2));
        return send(method, path, body: body, retries: retries - 1);
      } else {
        throw Exception('Error calling api and no retries left');
      }
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
    return accessToken;
  }
}
