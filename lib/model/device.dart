import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../reporting/error_logger.dart';

@immutable
class Device {
  final String id;
  final String name;
  final String? platform;
  final String? userId;

  const Device(this.id, this.name, this.platform, this.userId);

  Device withName(String name) {
    return Device(
      id,
      name,
      platform,
      userId,
    );
  }

  String get displayId {
    if (id.length < 5) {
      ErrorLogger.logSimpleError(
          'invalidIdForDisplayId', <String, String>{'id': id});
      return '';
    }
    return id.substring(0, 5);
  }

  IconData get icon {
    var isDesktop = platform == 'macos' || platform == 'windows';
    return isDesktop ? Icons.laptop : Icons.phone_android;
  }

  static Device decode(Map<String, dynamic> data) {
    return Device(data['id'] as String, data['name'] as String,
        data['platform'] as String?, data['userId'] as String?);
  }

  Map<String, dynamic> encode() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'platform': platform,
      'userId': userId,
    };
  }
}

class SelectedDeviceNotifier extends StateNotifier<Device?> {
  SelectedDeviceNotifier() : super(null);

  Device? getDevice() {
    return state;
  }

  void setDevice(Device? device) {
    state = device;
  }
}

final selectedDeviceProvider =
    StateNotifierProvider<SelectedDeviceNotifier, Device?>((ref) {
  return SelectedDeviceNotifier();
});
