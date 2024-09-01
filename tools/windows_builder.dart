import 'dart:io';

import 'command_runner.dart';
import 'tools_config.dart';

class WindowsAppBuilder {
  build() async {
    await setupWindows((Function runWinCommand) async {
      var repoPath = Config.windowsVmRepoPath;
      runWinCommand('cd "$repoPath" && git reset --hard && git pull -r');
      runWinCommand('cd "$repoPath" && flutter pub get');
      runWinCommand('cd "$repoPath" && dart run msix:create');
      var localMsixPath = '${Config.localRepoPath}/build/airdash.msix';
      fetchWindowsFile(Config.windowsVmMsixPath, localMsixPath);
    });
  }

  setupWindows(Function ready) async {
    print('Running: vmrun start ${Config.localWindowsVmPath} nogui');
    await Process.start('vmrun', ['start', Config.localWindowsVmPath, 'nogui'],
        environment: Config.env);
    await Future<void>.delayed(const Duration(seconds: 1));
    await ready(runWindowsCommand);
    runLocalCommand('vmrun suspend ${Config.localWindowsVmPath}');
  }

  void runWindowsCommand(String commandStr) {
    print('Running on windows: $commandStr');

    var exitCodeCommand =
        'echo _exit_code_\$? >> "${Config.windowsVmOutputPath}"';
    var command =
        '$commandStr &> "${Config.windowsVmOutputPath}" ; $exitCodeCommand';
    var result = runUserVmRunCommand(
        'runScriptInGuest', [Config.windowsVmBashPath, command]);
    if (result.exitCode != 0) {
      _printProcessResult(result);
      print('Local command failed with: ${result.exitCode}');
      print(StackTrace.current);
      throw Exception('Error');
    }

    fetchWindowsFile(Config.windowsVmOutputPath, Config.localStdoutPath, true);

    var stdoutFile = File(Config.localStdoutPath);
    var content = stdoutFile.readAsStringSync().trim();
    var stdoutParts = content.split('_exit_code_');
    exitCode = int.parse(stdoutParts[1]);
    content =
        stdoutParts[0].trim().split('\n').map((it) => '-    $it').join('\n');
    stdoutFile.deleteSync();

    if (content.isNotEmpty) print(content);

    if (exitCode != 0) {
      _printProcessResult(result);
      print('Windows command failed with: $exitCode');
      print(StackTrace.current);
      exit(exitCode);
    }
  }

  ProcessResult runUserVmRunCommand(String command, List<String> args) {
    return Process.runSync('vmrun', environment: Config.env, [
      '-gu',
      Config.windowsVmUser,
      '-gp',
      Config.windowsVmPassword,
      command,
      Config.localWindowsVmPath,
      ...args
    ]);
  }

  void fetchWindowsFile(String windowsPath, String localPath,
      [bool silent = false]) {
    var result = runUserVmRunCommand(
        'CopyFileFromGuestToHost', [windowsPath, localPath]);
    _printProcessResult(result);
    result = runUserVmRunCommand('runScriptInGuest', ['', 'del $windowsPath']);
    _printProcessResult(result);
    if (!silent) print('Finished copy to $localPath');
  }

  void _printProcessResult(ProcessResult result) {
    String content = result.stdout.toString().trim();
    content += result.stderr.toString().trim();
    var printableContent = '-   ${content.split('\n').join('\n    ')}';
    if (content.isNotEmpty) print(printableContent);
  }
}
