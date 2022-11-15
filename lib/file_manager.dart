import 'dart:io';

import 'package:airdash/reporting/analytics_logger.dart';
import 'package:airdash/reporting/error_logger.dart';
import 'package:airdash/reporting/logger.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'helpers.dart';
import 'model/payload.dart';

class FileManager {
  var pendingClean = false;

  Future<File> safeCopyToDownloads(File tmpFile) async {
    if (!isDesktop()) {
      return tmpFile;
    }
    try {
      var downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        return tmpFile;
      }
      var filename = getFilename(tmpFile);

      int i = 0;
      while (true) {
        var newFilename = i == 0 ? filename : '$i $filename';
        var file = File('${downloadsDir.path}/$newFilename');
        var exists = await file.exists();
        if (!exists) {
          var moved = await moveFile(tmpFile, file);
          logger("RECEIVER: File received and copied to: ${moved.path}");
          return moved;
        } else {
          i += 1;
          logger('RECEIVER: File already existed ${file.path}');
        }
      }
    } catch (error, stack) {
      ErrorLogger.logStackError('moveToDownloadsFailed', error, stack);
      return tmpFile;
    }
  }

  Future<File> moveFile(File source, File target) async {
    try {
      return source.rename(target.path);
    } catch (error) {
      var newFile = await source.copy(target.path);
      await source.delete();
      return newFile;
    }
  }

  Future cleanUsedFiles(List<Payload> selectedPayloads, File? receivedFile,
      String? receivingStatus) async {
    if (pendingClean) return;
    print('HOME: Starting cleaning used files...');
    pendingClean = true;

    if (receivingStatus != null) {
      // Needs to cancel to avoid deleting temporary files
      // Could be improved by checking specific active transfers
      print('HOME: Canceling file clean due to active transfer');
      return;
    }

    // Could potentially be performance heavy so delay to after start
    await Future<void>.delayed(const Duration(seconds: 3));

    var tmpDir = await getTemporaryDirectory();
    print('Temporary dir: ${tmpDir.path}');
    var prefs = await SharedPreferences.getInstance();
    var tmpFiles = prefs.getStringList('temporary_files') ?? [];
    for (var path in tmpFiles.toList()) {
      var selectedPaths =
          selectedPayloads.whereType<FilePayload>().map((it) => it.file.path);
      if (receivedFile?.path == path || selectedPaths.contains(path)) {
        print('HOME: Skipping delete of active file $path');
        continue;
      }

      // Remove file no matter if deletion succeeds or not
      tmpFiles.remove(path);
      prefs.setStringList('temporary_files', tmpFiles);

      try {
        var file = File(path);
        if (await file.exists()) {
          // Only delete files in temporary directory. On desktop and potentially
          // in some mobile uses the files are the original paths
          if (!path.startsWith(tmpDir.path)) {
            print('HOME: Not in tmp directory $path');
            continue;
          }
          await file.delete();
          print('HOME: Deleted used file $path');
        } else {
          print('HOME: Used file did not exists $path');
        }
      } catch (error, stack) {
        ErrorLogger.logStackError('usedFileDeletionError', error, stack);
      }
    }
    pendingClean = false;
  }

  Future openFinder(File file) async {
    if (!Platform.isMacOS) throw Exception('Not supported');

    String path = file.path;
    logger('MAIN: Will open folder at: $path');
    await communicatorChannel.invokeMethod<void>('openFinder', {'url': path});

    var props = await fileProperties(file);
    AnalyticsEvent.fileActionTaken.log(<String, dynamic>{
      'Action': 'File Manager',
      ...props,
    });
  }

  Future openParentFolder(File file) async {
    if (Platform.isMacOS) {
      await openFinder(file);
    } else {
      var folderPath = file.parent.path;
      var encodedFolderPath = Uri.encodeFull(folderPath);
      var folderUrl = Uri.parse('file:$encodedFolderPath');
      if (!await launchUrl(folderUrl)) {
        throw Exception('launchFolderUrlFalse');
      }
    }
  }
}
