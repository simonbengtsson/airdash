import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers.dart';
import '../transfer/connector.dart';
import 'device.dart';

class ValueStore {
  SharedPreferences prefs;

  ValueStore(this.prefs);

  Future<void> persistState(Connector? connector, Device currentDevice,
      List<Device> devices, WidgetRef ref) async {
    var prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'receivers', devices.map((r) => jsonEncode(r.encode())).toList());
    Device? selectedDevice =
        ref.read(selectedDeviceProvider.notifier).getDevice();
    if (selectedDevice != null) {
      await prefs.setString('selectedReceivingDeviceId', selectedDevice.id);
    } else {
      await prefs.remove('selectedReceivingDeviceId');
    }
    await prefs.setString('deviceName', currentDevice.name);
    connector?.localDevice = currentDevice;
  }

  bool isTrayModeEnabled() {
    return prefs.getBool('isTrayModeEnabled') ?? false;
  }

  Future<bool> toggleTrayModeEnabled() async {
    var enabled = !isTrayModeEnabled();
    await prefs.setBool('isTrayModeEnabled', enabled);
    return enabled;
  }

  Future<String> getDeviceId() async {
    var deviceId = prefs.getString('deviceId') ?? '';
    if (deviceId.length < 5) {
      deviceId = generateId(28);
      await prefs.setString('deviceId', deviceId);
    }
    return deviceId;
  }

  Future<Directory?> getFileLocation() async {
    String? custom;
    if (Platform.isMacOS) {
      custom =
          await communicatorChannel.invokeMethod<String>('getFileLocation');
    } else {
      custom = prefs.getString('customFileLocation');
    }
    if (custom == null) {
      var downloadsDir = await getDownloadsDirectory();
      return downloadsDir;
    } else {
      return Directory(custom);
    }
  }

  Future<void> setFileLocation(String? locationPath) async {
    if (Platform.isMacOS) {
      await communicatorChannel.invokeMethod<void>(
          'saveFileLocationBookmark', {'url': locationPath});
      return;
    }
    if (locationPath != null && locationPath.isNotEmpty) {
      await prefs.setString('customFileLocation', locationPath);
    } else {
      await prefs.remove('customFileLocation');
    }
  }

  Future<bool> setDeviceName(String name) {
    return prefs.setString('deviceName', name);
  }

  Future<String> getDeviceName() async {
    var deviceName = prefs.getString('deviceName') ?? '';
    if (deviceName.isEmpty) {
      final deviceInfoPlugin = DeviceInfoPlugin();
      final deviceInfo = await deviceInfoPlugin.deviceInfo;
      var info = deviceInfo.data;
      deviceName =
          info['name'] as String? ?? info['computerName'] as String? ?? '';
      if (deviceName.isEmpty) {
        deviceName =
            info['manufacturer'] as String? ?? Platform.operatingSystem;
        deviceName = deviceName.capitalize();
      }
      prefs.setString('deviceName', deviceName);
    }
    return deviceName;
  }

  List<Device> getReceivers() {
    var list = prefs.getStringList('receivers') ?? [];
    return list
        .map((r) => Device.decode(jsonDecode(r) as Map<String, dynamic>))
        .toList();
  }

  Device? getSelectedDevice() {
    var receivers = getReceivers();
    var selectedDeviceId = prefs.getString('selectedReceivingDeviceId');
    return receivers
        .where((it) => it.id == selectedDeviceId)
        .toList()
        .tryGet(0);
  }

  void updateStartValues() {
    var firstSeenAt = prefs.getString('firstSeenAt');
    if (firstSeenAt == null) {
      var date = DateTime.now().toIso8601String();
      prefs.setString('firstSeenAt', date);
    }

    int appOpens = prefs.getInt('appOpenCount') ?? 0;
    appOpens++;
    prefs.setInt('appOpenCount', appOpens);
  }
}
