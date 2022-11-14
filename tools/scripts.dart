import 'dart:convert';
import 'dart:io';

import 'app_store_version_submitter.dart';
import 'command_runner.dart';
import 'linux_submitter.dart';
import 'microsoft_store_submitter.dart';
import 'tools_config.dart';
import 'version_editor.dart';
import 'windows_builder.dart';

Future main(List<String> args) async {
  var script = args.isEmpty ? null : args.first;
  if (script == 'app_env') {
    var appEnvJson = jsonEncode(Config.getAppEnv());
    var commentStr = "// Generated file. Do not edit.";
    var codeStr = "var environment = <String, String>$appEnvJson;";
    var file = File('./lib/env.dart');
    file.writeAsStringSync('$commentStr\n$codeStr');
    print('Updated app env');
  } else if (script == 'bump') {
    VersionEditor().bumpPatchVersion();
  } else if (script == 'release') {
    await release();
  } else if (script == 'win') {
    await WindowsAppBuilder().build();
    await MicrosoftStoreSubmitter().submit();
  } else if (script == 'play') {
    VersionEditor().bumpPatchVersion();
  } else {
    print('Invalid script: $script');
  }
}

Future release() async {
  var startedAt = DateTime.now();
  var startedTimeStr = startedAt.toIso8601String().substring(11, 19);
  print('$startedTimeStr Starting build...');
  var version = VersionEditor().readCurrentVersion();

  version = VersionEditor().bumpPatchVersion();

  runLocalCommand('flutter build macos');
  runLocalCommand(
      'fastlane run build_mac_app export_team_id:"${Config.appStoreTeamId}" workspace:macos/Runner.xcworkspace output_directory:build');
  runLocalCommand(
      'xcrun altool --upload-app --type macos -f build/AirDash.pkg --apiKey ${Config.appStoreConnectApiKeyName} --apiIssuer ${Config.appStoreConnectIssuerId}');

  runLocalCommand('flutter build ipa');
  runLocalCommand(
      'xcrun altool --upload-app --type ios -f build/ios/ipa/*.ipa --apiKey ${Config.appStoreConnectApiKeyName} --apiIssuer ${Config.appStoreConnectIssuerId}');

  runLocalCommand('flutter build appbundle');
  runLocalCommand('flutter build apk');
  runLocalCommand(
      'cp build/app/outputs/flutter-apk/app-release.apk build/AirDash.apk');
  runLocalCommand(
      'fastlane upload_to_play_store --aab ${Config.localAabPath} --package_name io.flown.airdash --json_key ${Config.googlePlayKeyPath}');

  await WindowsAppBuilder().build();

  await AppStoreVersionSubmitter().submit();
  await MicrosoftStoreSubmitter().submit();

  await SnapStoreSubmitter().buildAndSubmit();

  runLocalCommand(
      'gh release create v${version.join('.')} build/AirDash.msix build/AirDash.apk --notes "See what\'s new in the [release notes](https://github.com/simonbengtsson/airdash/blob/master/CHANGELOG.md). The msix and apk files are included as assets below, but the update will soon be available in all supported app stores."');

  var endedAt = DateTime.now();
  var endedAtTimeStr = endedAt.toIso8601String().substring(11, 19);
  print(
      '$endedAtTimeStr Done! Took ${(endedAt.difference(startedAt).inSeconds / 60).toStringAsFixed(1)} min');
}
