import 'dart:io';

import 'package:airdash/reporting/error_logger.dart';
import 'package:airdash/reporting/logger.dart';
import 'package:dbus/dbus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'dbus_open_file/dbus_open_file.dart';
import 'helpers.dart';
import 'model/payload.dart';
import 'model/value_store.dart';

class FileManager {
  var pendingClean = false;

  Future<File> safeCopyToFileLocation(File tmpFile) async {
    if (!isDesktop()) {
      return tmpFile;
    }
    try {
      var prefs = await SharedPreferences.getInstance();
      var downloadsDir = await ValueStore(prefs).getFileLocation();
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
      logger("ERROR: $error");
      ErrorLogger.logStackError('moveToDownloadsFailed', error, stack);
      return tmpFile;
    }
  }

  Future openLinuxFile(File file) async {
    var client = DBusClient.session();
    var openUri = OrgFreedesktopPortalOpenURI(
      client,
      'org.freedesktop.portal.Desktop',
      path: DBusObjectPath('/org/freedesktop/portal/desktop'),
    );
    await openUri.callOpenDirectory(
      'org.freedesktop.portal.Desktop',
      DBusUnixFd(ResourceHandle.fromFile(
          await File('/home/simon/Desktop/names.txt').open())),
      {},
    );
    print('Opened linux file');
  }

  Future<File> moveFile(File source, File target) async {
    try {
      return await source.rename(target.path);
    } catch (error) {
      var newFile = await source.copy(target.path);
      await source.delete();
      return newFile;
    }
  }

  Future cleanUsedFiles(Payload? selectedPayload, List<File> receivedFiles,
      bool isTransferActive) async {
    if (pendingClean) return;
    print('FILE_MANAGER: Starting cleaning used files...');
    pendingClean = true;

    if (isTransferActive) {
      // Needs to cancel to avoid deleting temporary files
      // Could be improved by checking specific active transfers
      print('FILE_MANAGER: Canceling file clean due to active transfer');
      return;
    }

    // Could potentially be performance heavy so delay to after start
    await Future<void>.delayed(const Duration(seconds: 3));

    var tmpDir = await getTemporaryDirectory();
    print('Temporary dir: ${tmpDir.path}');
    var prefs = await SharedPreferences.getInstance();
    var tmpFiles = prefs.getStringList('temporary_files') ?? [];
    for (var path in tmpFiles.toList()) {
      var selectedPaths = selectedPayload is FilePayload
          ? selectedPayload.files.map((it) => it.path)
          : <String>[];
      if (receivedFiles.map((it) => it.path).contains(path) ||
          selectedPaths.contains(path)) {
        print('FILE_MANAGER: Skipping delete of active file $path');
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
            print('FILE_MANAGER: Not in tmp directory $path');
            continue;
          }
          await file.delete();
          print('FILE_MANAGER: Deleted used file $path');
        } else {
          print('FILE_MANAGER: Used file did not exists $path');
        }
      } catch (error, stack) {
        ErrorLogger.logStackError('usedFileDeletionError', error, stack);
      }
    }
    pendingClean = false;
  }

  Future openFolder(String filePath) async {
    if (Platform.isMacOS) {
      await _openFinder(filePath);
    } else {
      var encodedFolderPath = Uri.encodeFull(filePath);
      var folderUrl = Uri.parse('file:$encodedFolderPath');
      if (!await launchUrl(folderUrl)) {
        throw Exception('launchFolderUrlFalse');
      }
    }
  }

  Future _openFinder(String filePath) async {
    if (!Platform.isMacOS) throw Exception('Not supported');

    logger('MAIN: Will open folder at: $filePath');
    await communicatorChannel
        .invokeMethod<void>('openFinder', {'url': filePath});
  }
}
