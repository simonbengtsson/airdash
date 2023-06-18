import 'dart:io';

import 'package:airdash/model/value_store.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../helpers.dart';

void openFileLocationDialog(BuildContext context, ValueStore valueStore) async {
  var fileLocationPath = await valueStore.getFileLocation();
  if (Platform.isMacOS) {
    await communicatorChannel.invokeMethod<void>('endFileLocationAccess');
  }
  if (context.mounted) {
    showDialog<void>(
      context: context,
      builder: (_) => FileLocationDialog(
          fileLocationPath: fileLocationPath?.path, valueStore: valueStore),
    );
  }
}

class FileLocationDialog extends StatefulWidget {
  final ValueStore valueStore;
  final String? fileLocationPath;

  const FileLocationDialog(
      {Key? key, required this.fileLocationPath, required this.valueStore})
      : super(key: key);

  @override
  State<FileLocationDialog> createState() => _FileLocationDialogState();
}

class _FileLocationDialogState extends State<FileLocationDialog> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 250,
                  child: TextFormField(
                    enabled: false,
                    style: const TextStyle(fontSize: 14, fontFamily: 'courier'),
                    initialValue: widget.fileLocationPath ?? '-',
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: () async {
                    var directoryPath =
                        await FilePicker.platform.getDirectoryPath(
                      lockParentWindow: true,
                      initialDirectory: widget.fileLocationPath,
                    );
                    if (directoryPath != null) {
                      await widget.valueStore.setFileLocation(directoryPath);
                      print('Selected $directoryPath');
                      if (mounted) {
                        Navigator.pop(context);
                      }
                    }
                  },
                  icon: const Icon(Icons.folder_open_sharp),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Flexible(
              child: Text('The folder which received files will be stored')),
        ],
      ),
      actions: [
        TextButton(
          child: const Text('Done'),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ],
    );
  }
}
