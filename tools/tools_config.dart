import 'dart:convert';
import 'dart:io';

class Config {
  static final env = _parseEnv();

  static final localRepoPath = (Platform.script.path.split('/')
        ..removeLast()
        ..removeLast())
      .join('/');

  static final windowsApiClientId = _env('WINDOWS_API_CLIENT_ID');
  static final windowsApiClientSecret = _env('WINDOWS_API_CLIENT_SECRET');
  static final windowsApiTenantId = _env('WINDOWS_API_TENANT_ID');
  static final windowsApiAppId = _env('WINDOWS_API_APP_ID');

  static final windowsVmUser = _env('WINDOWS_VM_USER');
  static final windowsVmPassword = _env('WINDOWS_VM_USER_PASSWORD');
  static const windowsVmBashPath = r'C:\Program Files\Git\bin\bash.exe';

  static final linuxVmUser = _env('LINUX_VM_USER');
  static final linuxVmPassword = _env('LINUX_VM_USER_PASSWORD');
  static final linuxVmRepoPath = _env('LINUX_VM_REPO_PATH');
  static final linuxVmOutputPath = '$linuxVmRepoPath/build/stdout.txt';
  static final localLinuxVmPath = _env('LINUX_VM_PATH');

  static final windowsVmRepoPath = _env('WINDOWS_VM_REPO_PATH');
  static final windowsVmOutputPath = '$windowsVmRepoPath\\build\\stdout.txt';
  static final windowsVmMsixPath =
      '$windowsVmRepoPath\\build\\windows\\runner\\Release\\AirDash.msix';

  static final localWindowsVmPath = _env('WINDOWS_VM_PATH');
  static final localStdoutPath = '$localRepoPath/build/stdout.txt';
  static final localPubspecPath = '$localRepoPath/pubspec.yaml';
  static final localRunnerRcPath = '$localRepoPath/windows/runner/Runner.rc';

  static final localAabPath =
      '$localRepoPath/build/app/outputs/bundle/release/app-release.aab';
  static final appStoreConnectIssuerId = _env('APP_STORE_CONNECT_ISSUER_ID');
  static final appStoreConnectApiKeyName = _env('APP_STORE_CONNECT_API_KEY');
  static final appStoreConnectKeyPath = _env('APP_STORE_CONNECT_KEY_PATH');
  static final appStoreAppId = _env('APP_STORE_APP_ID');
  static final appStoreTeamId = _env('APP_STORE_TEAM_ID');
  static final googlePlayKeyPath = _env('GOOGLE_PLAY_KEY_PATH');

  static String _env(String key) {
    var value = env[key];
    if (value == null) throw Exception('Missing env variable $key');
    return value;
  }

  static Map<String, String> getAppEnv() {
    var appEnv = <String, String>{};
    for (var it in env.entries) {
      if (it.key.startsWith('__APP__')) {
        appEnv[it.key] = it.value;
      }
    }
    return appEnv;
  }

  static Map<String, String> _parseEnv() {
    var repoPath = Config.localRepoPath;
    if (Platform.isWindows && repoPath.startsWith('/')) {
      repoPath = repoPath.substring(1);
    }

    var content = File('$repoPath/.env').readAsStringSync();
    Map<String, String> values = {};
    for (var line in content.split('\n')) {
      if (line.trim().isEmpty) continue;
      if (line.trim().startsWith('#')) continue;

      var parts = line.split('=');
      values[parts.removeAt(0)] = parts.join('=').trim();
    }
    return values;
  }
}

String formatJson(dynamic object) {
  var encoder = const JsonEncoder.withIndent('  ');
  return encoder.convert(object);
}
