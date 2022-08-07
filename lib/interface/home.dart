import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firedart/firestore/firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' hide MenuItem;
import 'package:flutter/services.dart';
import 'package:grpc/grpc.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:window_manager/window_manager.dart';
//import 'package:beacon_broadcast/beacon_broadcast.dart';

import '../config.dart';
import '../file_manager.dart';
import '../helpers.dart';
import '../intent_receiver.dart';
import '../interface/pairing_dialog.dart';
import '../model/device.dart';
import '../model/payload.dart';
import '../model/user.dart';
import '../model/value_store.dart';
import '../reporting/analytics_logger.dart';
import '../reporting/error_logger.dart';
import '../reporting/logger.dart';
import '../transfer/connector.dart';
import '../transfer/signaling.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key}) : super(key: key);

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage>
    with TrayListener, WindowListener {
  Connector? connector;
  final IntentReceiver intentReceiver = IntentReceiver();
  final signaling = Signaling();
  final fileManager = FileManager();
  late final ValueStore valueStore;

  List<Log> logs = [];
  String? loggingMode;
  bool isDragging = false;

  Device? currentDevice;

  List<Device> devices = [];

  File? receivedFile;
  List<Payload> selectedPayloads = [];
  Device? selectedDevice;
  String? sendingStatus;
  String? receivingStatus;

  var isPickingFile = false;

  static const communicatorChannel =
      MethodChannel('io.flown.airdash/communicator');

  @override
  void initState() {
    windowManager.addListener(this);
    trayManager.addListener(this);
    super.initState();

    init();
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    trayManager.removeListener(this);
    intentReceiver.intentDataStreamSubscription?.cancel();
    intentReceiver.intentDataStreamSubscription = null;
    intentReceiver.intentTextStreamSubscription?.cancel();
    intentReceiver.intentTextStreamSubscription = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragDone: (detail) async {
        logger('DROP: Files dropped ${detail.files.length}');
        var payloads =
            detail.files.map((it) => FilePayload(File(it.path))).toList();
        await setPayload(payloads, 'dropped');
      },
      onDragEntered: (detail) {
        setState(() {
          isDragging = true;
        });
        showDropOverlay();
      },
      onDragExited: (detail) {
        setState(() {
          isDragging = false;
        });
        Navigator.pop(context);
      },
      child: Scaffold(
        appBar: null,
        body: Column(
          children: [
            if (currentDevice != null) buildOwnDeviceView(currentDevice!),
            Expanded(
              child: SingleChildScrollView(
                child: SafeArea(
                  top: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (receivingStatus != null)
                        buildReceivingStatusBox(receivingStatus!),
                      if (receivedFile != null) buildFilesCard(receivedFile!),
                      buildSelectFileArea(),
                      buildReceiverButtons(devices),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ButtonTheme(
                            height: 60,
                            minWidth: 200,
                            child: renderSendButton(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  init() async {
    try {
      await start().timeout(const Duration(seconds: 10));
      selectDebugFile();
    } catch (error, stack) {
      ErrorLogger.logStackError('startError', error, stack);
      showSnackBar('Could not connect. Check your internet connection.');
    }
  }

  Future start() async {
    var prefs = await SharedPreferences.getInstance();
    valueStore = ValueStore(prefs);

    if (isMobile()) {
      observeIntentFile();
    }

    var deviceId = await valueStore.getDeviceId();
    var deviceName = await valueStore.getDeviceName();

    var user = UserState(prefs).getCurrentUser();
    var localDevice =
        Device(deviceId, deviceName, Platform.operatingSystem, user?.id);
    setState(() {
      currentDevice = localDevice;
    });

    connector = Connector(
        localDevice, signaling, SignalingObserver(deviceId, signaling));
    devices = valueStore.getReceivers();
    selectedDevice = valueStore.getSelectedDevice();

    await connector!.observe((payload, error, statusUpdate) async {
      if (payload is UrlPayload) {
        await launchUrl(payload.httpUrl, mode: LaunchMode.externalApplication);
        showSnackBar('URL opened');
        setReceivedFile(null, null);
        return;
      }
      File? tmpFile;
      if (payload is FilePayload) {
        tmpFile = payload.file;
      }
      String? newReceivingStatus;
      if (tmpFile != null) {
        try {
          // Only files created by app can be opened on macos without getting
          // permission errors or permission dialog.
          tmpFile = await fileManager.safeCopyToDownloads(tmpFile);
          showSnackBar('File received');
        } catch (error, stack) {
          ErrorLogger.logStackError('downloadsCopyError', error, stack);
          showSnackBar('File could not be saved');
        }
      } else if (error != null) {
        if (error is AppException) {
          showSnackBar(error.userError);
        } else {
          showSnackBar('Could not receive file. Try again.');
        }
      } else {
        newReceivingStatus = statusUpdate;
      }
      setReceivedFile(tmpFile, newReceivingStatus);
    });

    connector!.startPing();

    fileManager.cleanUsedFiles(selectedPayloads, receivedFile, receivingStatus);

    try {
      await Analytics.updateProfile(localDevice.id);
      await updateConnectionConfig();
    } catch (error, stack) {
      ErrorLogger.logStackError('infoUpdateError', error, stack);
    }

    //startBluetooth();
  }
/*
  BeaconBroadcast beaconBroadcast = BeaconBroadcast();
  startBluetooth() {
    beaconBroadcast
        .setUUID('39ED98FF-2900-441A-802F-9C398FC199D2')
        .setMajorId(1)
        .setMinorId(100)
        .start();
  }
*/

  updateConnectionConfig() async {
    var doc = await Firestore.instance
        .collection('appInfo')
        .document('appInfo')
        .get();
    var json = jsonEncode(doc.map);
    var prefs = await SharedPreferences.getInstance();
    prefs.setString('appInfo', json);
    logger('Updated cached appInfo');
  }

  @override
  void onWindowFocus() {
    // Make sure to call setState once (window manager)
  }

  @override
  void onWindowEvent(String eventName) {}

  @override
  void onWindowBlur() {
    if (!isPickingFile && Platform.isMacOS && Config.enableDesktopTray) {
      windowManager.close();
    }
  }

  @override
  void onWindowClose() {
    if (!Config.enableDesktopTray) {
      exit(1);
    }
  }

  @override
  void onTrayIconMouseDown() async {
    if (await windowManager.isVisible()) {
      await windowManager.close();
    } else {
      await windowManager.show();
    }
    print('tray icon mouse down');
  }

  @override
  void onTrayIconRightMouseDown() async {
    print('tray icon right mouse down');
    await trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconRightMouseUp() {
    print('tray icon right mouse up');
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) async {
    logger('TRAY: Menu item clicked ${menuItem.key}');
    if (menuItem.key == 'show_window') {
      logger('TRAY: Should focus/open window');
      await windowManager.show();
    } else if (menuItem.key == 'exit_app') {
      exit(1);
    }
  }

  observeIntentFile() async {
    intentReceiver.observe((payload, error) async {
      if (payload == null) {
        showToast(error ?? 'Could not handle payload');
        return;
      }
      if (payload is FilePayload) {
        logger('HOME: Payload intent ${payload.file.path}');
      } else if (payload is UrlPayload) {
        print('HOME: Url intent, ${payload.httpUrl.toString()}');
      }
      await setPayload([payload], 'intent');
    });
  }

  showSnackBar(String message) {
    if (mounted) {
      var bar = SnackBar(content: Text(message));
      ScaffoldMessenger.of(context).showSnackBar(bar);
    }
  }

  selectDebugFile() async {
    if (kDebugMode && Platform.isMacOS) {
      try {
        var dir = await getApplicationDocumentsDirectory();
        var file = File('${dir.path}/airdash.flown.io.testfile.txt');
        if (await file.exists()) {
          setState(() {
            selectedPayloads = [FilePayload(file)];
          });
        }
      } catch (error) {
        logger('Could not set test file $error');
      }
    }
  }

  sendPayload(Device receiver, List<Payload> payloads) async {
    var payload = payloads.tryGet(0);
    if (payload == null) {
      print('HOME: No payload');
      return;
    }
    if (payload is FilePayload && !(await payload.file.exists())) {
      showToast('File not found. Try again.');
      setState(() {
        selectedPayloads = [];
      });
      return;
    }
    if (payloads.length > 1) {
      print('HOME: Multiple payloads, selecting first');
    }
    setState(() {
      sendingStatus = 'Connecting...';
    });
    try {
      var fractionDigits = await getFractionDigits(payload);
      String? lastProgressStr;
      int lastDone = 0;
      var lastTime = DateTime.now();
      await connector!.sendFile(receiver, payloads, (done, total) {
        var progress = done / total;
        var progressStr = (progress * 100).toStringAsFixed(fractionDigits);
        var speedStr = '';
        if (lastProgressStr != progressStr) {
          var diff = DateTime.now().difference(lastTime);
          var diffBytes = done - lastDone;
          speedStr = ' (${formatDataSpeed(diffBytes, diff)})';
          setState(() {
            sendingStatus = 'Sending $progressStr%$speedStr';
          });
          lastDone = done;
          lastTime = DateTime.now();
          lastProgressStr = progressStr;
        }
      });
      showSnackBar('File sent');
      setState(() {
        sendingStatus = null;
        selectedPayloads = [];
      });
    } catch (error, stack) {
      logger('SENDER: Send file error "$error"');
      String errorMessage;
      if (error is AppException) {
        errorMessage = error.userError;
        ErrorLogger.logStackError(error.type, error, stack);
      } else if (error is GrpcError && error.code == 14) {
        errorMessage = "Sending failed. Try again.";
        ErrorLogger.logStackError('internetSenderError', error, stack);
      } else {
        errorMessage = "Sending failed. Try again.";
        ErrorLogger.logStackError('unknownSenderError', error, stack);
      }
      showSnackBar(errorMessage);
      setState(() {
        sendingStatus = null;
      });
    }
  }

  Future<int> getFractionDigits(Payload payload) async {
    var payloadSize = 100;
    if (payload is FilePayload) {
      payloadSize = await payload.file.length();
    }
    var payloadMbSize = payloadSize / 1000000;
    return payloadMbSize > 1000 ? 1 : 0;
  }

  setReceivedFile(File? file, String? status) {
    setState(() {
      receivedFile = file;
      receivingStatus = status;
    });
    if (file != null) {
      addUsedFile(file);
    }
  }

  Future<void> openPairReceiverDialog(
      Device device, BuildContext context) async {
    AnalyticsEvent.pairingDialogShown.log();
    return showDialog(
        context: context,
        builder: (context) {
          return PairingDialog(
              localDevice: device,
              onPair: (receiver) async {
                setState(() {
                  devices.removeWhere((it) => it.id == receiver.id);
                  devices.add(receiver);
                  selectedDevice = receiver;
                });
                AnalyticsEvent.pairingCompleted.log({
                  'Device ID': receiver.id,
                  'Device Name': receiver.name,
                  'Device OS': receiver.platform ?? '',
                  'User ID': receiver.userId ?? '',
                });
                await persistState();
              });
        });
  }

  persistState() async {
    var prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'receivers', devices.map((r) => jsonEncode(r.encode())).toList());
    if (selectedDevice != null) {
      await prefs.setString('selectedReceivingDeviceId', selectedDevice!.id);
    } else {
      await prefs.remove('selectedReceivingDeviceId');
    }
    if (currentDevice != null) {
      await prefs.setString('deviceName', currentDevice!.name);
    }
    connector?.localDevice = currentDevice!;
  }

  Widget renderSendButton() {
    var disabled = selectedPayloads.isEmpty ||
        selectedDevice == null ||
        sendingStatus != null;
    return OutlinedButton(
      onPressed: disabled
          ? null
          : () {
              sendPayload(selectedDevice!, selectedPayloads);
            },
      child: Text(
        sendingStatus ?? "Send",
      ),
    );
  }

  Widget buildLog(List<Log> logs) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: logs.map((log) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 90,
              child: Text(log.time.toString().substring(10, 23),
                  style: const TextStyle(fontSize: 12)),
            ),
            SelectableText(log.message,
                style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'Courier',
                    color: Color(0xff555555))),
          ]);
        }).toList(),
      ),
    );
  }

  openPhotoAndFileBottomSheet() {
    showModalBottomSheet(
        context: context,
        builder: (context) {
          return SafeArea(
            child: Wrap(
              children: [
                ListTile(
                  leading: const Icon(Icons.photo),
                  title: const Text('Media'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    openFilePicker(FileType.media);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.description),
                  title: const Text('Files'),
                  onTap: () async {
                    Navigator.of(context).pop();
                    openFilePicker(FileType.any);
                  },
                ),
              ],
            ),
          );
        });
  }

  openFilePicker(FileType type) async {
    isPickingFile = true;
    var result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Pick File',
      type: type,
      lockParentWindow: true,
      withData: false,
      allowCompression: false,
      withReadStream: true,
    );
    if (result != null && result.files.isNotEmpty) {
      var file = File(result.files.first.path!);
      var param = type == FileType.media ? 'media' : 'fileManager';
      await setPayload([FilePayload(file)], param);
      logger('HOME: File selected ${file.path}');
    }
    isPickingFile = false;
    if (isDesktop()) {
      await windowManager.show();
    }
  }

  setPayload(List<Payload> payloads, String source) async {
    for (var payload in payloads) {
      if (payload is FilePayload) {
        try {
          var length = await payload.file.length();
          if (length <= 0) {
            throw Exception('Invalid file length $length');
          }
          addUsedFile(payload.file);
        } catch (error, stack) {
          ErrorLogger.logStackError('payloadSelectError', error, stack);
          showToast('Could not read selected file');
          return;
        }
      }
    }
    AnalyticsEvent.payloadSelected.log({
      'Source': source,
      ...await payloadProperties(payloads),
    });
    setState(() {
      selectedPayloads = payloads;
    });
  }

  openFile(File file) async {
    try {
      String path = file.path;
      if (Platform.isIOS) {
        logger('MAIN: Will open: $path');
        // Encode path to support filenames with spaces
        var encodedPath = Uri.encodeFull(path);
        await communicatorChannel
            .invokeMethod('openFile', {'url': encodedPath});
      } else if (Platform.isAndroid) {
        var launchUrl = file.path;
        logger('MAIN: Will open: $launchUrl');
        try {
          await communicatorChannel
              .invokeMethod('openFile', {'url': launchUrl});
        } catch (error, stack) {
          ErrorLogger.logStackError(
              'noInstalledAppCouldOpenFile', error, stack);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text("No installed app could open this file")));
        }
      } else {
        // Spaces not supported on macos but works when encoded
        var encodedPath = Uri.encodeFull(path);
        var url = Uri.parse('file:$encodedPath');
        logger('MAIN: Will open: ${url.path}');
        try {
          if (!await launchUrl(url)) {
            throw Exception('launchUrlErrorFalse');
          }
        } catch (error, stack) {
          ErrorLogger.logError(LogError('launchFileUrlError', error, stack, {
            'encodedPath': encodedPath,
            'rawPath': path,
          }));
          await fileManager.openParentFolder(file);
        }
      }
    } catch (error, stack) {
      ErrorLogger.logError(
          SevereLogError('openFileAndFolderError', error, stack, {
        'path': file.path,
      }));
      showToast('Could not open file');
    }
    var props = await fileProperties(file);
    AnalyticsEvent.fileActionTaken.log({
      'Action': 'Open',
      ...props,
    });
  }

  showToast(String message) {
    var bar = SnackBar(content: Text(message));
    ScaffoldMessenger.of(context).showSnackBar(bar);
  }

  Widget buildFilesCard(File file) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8, left: 16, right: 16),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: const BorderRadius.all(Radius.circular(10)),
          //color: Colors.grey[100],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 8.0, bottom: 0, right: 8),
              child: Row(
                children: [
                  buildSectionTitle('Received File'),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setReceivedFile(null, null);
                      fileManager.cleanUsedFiles(
                          selectedPayloads, receivedFile, receivingStatus);
                    },
                  ),
                ],
              ),
            ),
            ListTile(
              onTap: () {
                openFile(file);
              },
              trailing: IconButton(
                onPressed: () async {
                  if (isDesktop()) {
                    await fileManager.openParentFolder(file);
                  } else {
                    await openShareSheet(file, context);
                  }
                },
                icon: Icon(isDesktop()
                    ? Icons.folder_open
                    : (Platform.isIOS ? Icons.ios_share : Icons.share)),
              ),
              leading: Image.file(file, height: 40, fit: BoxFit.contain,
                  errorBuilder: (ctx, err, stack) {
                return const Icon(Icons.file_copy_outlined);
              }),
              title: Text(getFilename(file)),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  selectFile() {
    AnalyticsEvent.fileSelectionStarted.log();
    if (Platform.isIOS) {
      openPhotoAndFileBottomSheet();
    } else {
      openFilePicker(FileType.any);
    }
  }

  Map<String, bool> disabledKeys = {};

  Widget buildSelectFileArea() {
    var payload = selectedPayloads.tryGet(0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: buildSectionTitle('File to send')),
        if (payload == null)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(
                    left: 16, right: 16, bottom: 8, top: 8),
                child: Row(
                  children: [
                    TextButton(
                        onPressed: disabledKeys['selectFileButton'] != null
                            ? null
                            : () async {
                                setState(() =>
                                    disabledKeys['selectFileButton'] = true);
                                selectFile();
                                await Future.delayed(Duration(
                                    milliseconds: isDesktop() ? 2000 : 500));
                                setState(() =>
                                    disabledKeys.remove('selectFileButton'));
                              },
                        child: Row(
                          children: const [
                            Icon(Icons.add),
                            SizedBox(width: 10),
                            Text('Select File',
                                style:
                                    TextStyle(overflow: TextOverflow.ellipsis)),
                          ],
                        )),
                  ],
                ),
              ),
            ],
          ),
        if (payload is UrlPayload) buildSelectedUrlTile(payload.httpUrl),
        if (payload is FilePayload) buildSelectedFileTile(payload.file),
      ],
    );
  }

  buildSelectedUrlTile(Uri url) {
    var urlString = url.toString();
    if (urlString.length > 100) {
      urlString = '${urlString.substring(0, 97)}...';
    }
    return ListTile(
      leading: const Icon(Icons.link),
      title: Text(urlString),
      trailing: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () {
          setState(() {
            selectedPayloads = [];
          });
        },
      ),
    );
  }

  buildSelectedFileTile(File file) {
    return ListTile(
      leading: Image.file(file, height: 40, fit: BoxFit.contain,
          errorBuilder: (ctx, err, stack) {
        return const Icon(Icons.file_copy_outlined);
      }),
      title: Text(getFilename(file)),
      trailing: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () {
          setState(() {
            selectedPayloads = [];
          });
        },
      ),
    );
  }

  openShareSheet(File file, BuildContext context) async {
    String filename = getFilename(file);
    String filePath = file.path;
    final box = context.findRenderObject() as RenderBox?;
    if (box != null) {
      await Share.shareFiles([filePath],
          text: filename,
          subject: filename,
          sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size);
    }
    var props = await fileProperties(file);
    AnalyticsEvent.fileActionTaken.log({
      'Action': 'Share',
      ...props,
    });
  }

  showDropOverlay() {
    showGeneralDialog(
      context: context,
      barrierColor: Colors.white.withOpacity(0.95),
      barrierDismissible: false,
      barrierLabel: 'Dialog',
      transitionDuration: const Duration(milliseconds: 0),
      pageBuilder: (_, __, ___) {
        return const Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: Text('Drop File Here',
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: Colors.grey)),
          ),
        );
      },
    );
  }

  deleteDevice(Device device) {
    AnalyticsEvent.receiverDeleted.log({
      'Device ID': device.id,
      'Device Name': device.name,
      'Device OS': device.platform ?? '',
    });
    setState(() {
      devices = devices.where((r) => r.id != device.id).toList();
      selectedDevice = devices.firstOrNull;
      persistState();
    });
  }

  buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16),
      child: Text(text.toUpperCase(),
          style: const TextStyle(color: Colors.black54, fontSize: 13)),
    );
  }

  buildReceiverButtons(List<Device> devices) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 8),
          child: buildSectionTitle('Select Receiver'),
        ),
        ...devices.map((it) {
          var selected = selectedDevice?.id == it.id;
          return ListTile(
            onLongPress: () {
              showDialog(
                  context: context,
                  builder: (ctx) {
                    return AlertDialog(
                      title: const Text('Remove Device'),
                      content: const Text('Do you want to remove this device?'),
                      actions: [
                        TextButton(
                            onPressed: () async {
                              Navigator.of(ctx).pop();
                            },
                            child: const Text('Cancel')),
                        TextButton(
                            onPressed: () async {
                              Navigator.of(ctx).pop();
                              await deleteDevice(it);
                            },
                            child: const Text('Remove')),
                      ],
                    );
                  });
            },
            onTap: () {
              setState(() {
                selectedDevice = it;
              });
              AnalyticsEvent.receiverSelected.log({
                ...remoteDeviceProperties(it),
              });
              persistState();
            },
            selected: selected,
            trailing: selected ? const Icon(Icons.check) : null,
            selectedTileColor: Colors.grey[100],
            leading: Icon(it.icon),
            title: Text(it.name),
            subtitle: Text(it.displayId),
          );
        }).toList(),
        Padding(
          padding:
              const EdgeInsets.only(left: 16, right: 16, bottom: 16, top: 8),
          child: Row(
            children: [
              TextButton(
                  onPressed: currentDevice == null ||
                          disabledKeys['pairNewDevice'] != null
                      ? null
                      : () async {
                          setState(() => disabledKeys['pairNewDevice'] = true);
                          openPairReceiverDialog(currentDevice!, context);
                          await Future.delayed(
                              const Duration(milliseconds: 200));
                          setState(() => disabledKeys.remove('pairNewDevice'));
                        },
                  child: Row(
                    children: const [
                      Icon(Icons.add),
                      SizedBox(width: 10),
                      Text('Pair New Device',
                          style: TextStyle(overflow: TextOverflow.ellipsis)),
                    ],
                  )),
            ],
          ),
        ),
      ],
    );
  }

  buildOwnDeviceView(Device device) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            offset: Offset(0, 0),
            blurRadius: 10.0,
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16.0, top: 16),
              child: Text('THIS DEVICE ${kDebugMode ? ' (DEV)' : ''}',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
            ListTile(
              leading: Icon(device.icon),
              title: Text('${device.name}${kDebugMode ? '' : ''}'),
              subtitle: Text(device.displayId),
              trailing: IconButton(
                  onPressed: currentDevice == null
                      ? null
                      : () {
                          openSettingsDialog(currentDevice!);
                        },
                  icon: const Icon(Icons.settings)),
            ),
          ],
        ),
      ),
    );
  }

  openSettingsDialog(Device currentDevice) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
          title: const Text('Settings'),
          content: TextFormField(
            decoration: const InputDecoration(
              label: Text('This Device Name'),
            ),
            initialValue: currentDevice.name,
            onChanged: (text) async {
              setState(() {
                currentDevice.name = text;
              });
              await persistState();
            },
          ),
          actions: [
            TextButton(
              child: const Text('Licenses'),
              onPressed: () async {
                PackageInfo packageInfo = await PackageInfo.fromPlatform();
                var version = packageInfo.version;
                showLicensePage(
                  context: context,
                  applicationName: 'AirDash',
                  applicationVersion: 'v$version',
                );
              },
            ),
            TextButton(
              child: const Text('Done'),
              onPressed: () {
                Navigator.pop(context);
              },
            ),
          ]),
    );
  }

  Widget buildReceivingStatusBox(String statusMessage) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8, left: 16, right: 16),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey[300]!),
          borderRadius: const BorderRadius.all(Radius.circular(10)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(statusMessage),
        ),
      ),
    );
  }
}
