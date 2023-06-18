import 'dart:io';
import 'command_runner.dart';
import 'tools_config.dart';

class SnapStoreSubmitter {
  var linuxVmHelper = VirtualMachineHelper(Config.linuxVmUser,
      Config.linuxVmPassword, Config.localLinuxVmPath, '/bin/bash');

  Future<void> buildAndSubmit() async {
    await linuxVmHelper.runVmCommands((Function runVmCommand) async {
      var repoPath = Config.linuxVmRepoPath;
      runVmCommand(
          'cd "$repoPath" && rm -f build/stdout.txt && git reset --hard && git pull -r');
      runVmCommand('cd "$repoPath" && snapcraft clean --use-lxd');
      runVmCommand(
          'cd "$repoPath" && /home/simon/tools/flutter/bin/flutter build linux --release');
      runVmCommand(
          'cd "$repoPath" && snapcraft snap --output build/app.snap --use-lxd');
      runVmCommand(
          'cd "$repoPath" && export SNAPCRAFT_STORE_CREDENTIALS=${Config.snapcraftLoginCredentials} && snapcraft upload --release=stable build/app.snap');
      var vmSnapPath = '$repoPath/build/app.snap';
      var localSnapPath = '${Config.localRepoPath}/build/AirDash.snap';
      linuxVmHelper.fetchVmFile(vmSnapPath, localSnapPath);
    });
  }
}

class VirtualMachineHelper {
  String vmUser;
  String vmUserPassword;
  String vmPath;
  String bashPath;

  VirtualMachineHelper(
      this.vmUser, this.vmUserPassword, this.vmPath, this.bashPath);

  Future<void> runVmCommands(Function ready) async {
    print('Running: vmrun start $vmPath nogui');
    await Process.start('vmrun', ['start', vmPath, 'nogui'],
        environment: Config.env);
    await Future<void>.delayed(const Duration(seconds: 1));
    await ready((String cmdString) {
      _runVmCommand(
          cmdString, Config.linuxVmOutputPath, 'build/stdout.txt', bashPath);
    });
    runLocalCommand('vmrun suspend $vmPath');
  }

  void _runVmCommand(String commandStr, String outputPath,
      String localOutputPath, String bashPath) {
    print('Running on vm: $commandStr');

    var exitCodeCommand = 'echo _exit_code_\$? >> "$outputPath"';
    var command = '$commandStr &> "$outputPath" ; $exitCodeCommand';
    print(command);
    var result = runUserVmRunCommand('runScriptInGuest', [bashPath, command]);
    if (result.exitCode != 0) {
      _printProcessResult(result);
      print('Local command failed with: ${result.exitCode}');
      print(StackTrace.current);
      throw Exception('Error');
    }

    fetchVmFile(outputPath, localOutputPath, true);

    var stdoutFile = File(localOutputPath);
    var content = stdoutFile.readAsStringSync().trim();
    var stdoutParts = content.split('_exit_code_');
    exitCode = int.parse(stdoutParts[1]);
    content =
        stdoutParts[0].trim().split('\n').map((it) => '-    $it').join('\n');
    stdoutFile.deleteSync();

    if (content.isNotEmpty) print(content);

    if (exitCode != 0) {
      _printProcessResult(result);
      print('VM command failed with: $exitCode');
      print(StackTrace.current);
      exit(exitCode);
    }
  }

  void fetchVmFile(String vmPath, String localPath, [bool silent = false]) {
    var result =
        runUserVmRunCommand('CopyFileFromGuestToHost', [vmPath, localPath]);
    _printProcessResult(result);
    if (!silent) print('Finished copy to $localPath');
  }

  ProcessResult runUserVmRunCommand(String command, List<String> args) {
    return Process.runSync(
        'vmrun',
        environment: Config.env,
        ['-gu', vmUser, '-gp', vmUserPassword, command, vmPath, ...args]);
  }

  void _printProcessResult(ProcessResult result) {
    String content = result.stdout.toString().trim();
    content += result.stderr.toString().trim();
    var printableContent = '-   ${content.split('\n').join('\n    ')}';
    if (content.isNotEmpty) print(printableContent);
  }
}
