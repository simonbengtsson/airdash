import 'dart:io';

import 'tools_config.dart';

ProcessResult runLocalCommand(String commandStr, [silent = false]) {
  if (!silent) print('Running: $commandStr');
  var result =
      Process.runSync('/bin/zsh', ['-c', commandStr], environment: Config.env);

  if (result.exitCode != 0 || !silent) {
    String content = result.stdout.toString().trim();
    content += result.stderr.toString().trim();
    var printableContent = '-   ${content.split('\n').join('\n    ')}';
    if (content.isNotEmpty) print(printableContent);

    if (result.exitCode != 0) {
      print('Local command failed with: ${result.exitCode}');
      print(StackTrace.current);
      exit(result.exitCode);
    }
  }

  return result;
}
