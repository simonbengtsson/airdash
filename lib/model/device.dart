import 'package:flutter/material.dart';

import '../reporting/error_logger.dart';

class Device {
  String id;
  String name;
  String? platform;
  String? userId;

  Device(this.id, this.name, this.platform, this.userId);

  String get displayId {
    if (id.length < 5) {
      ErrorLogger.logSimpleError('invalidIdForDisplayId', {'id': id});
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
    return {
      'id': id,
      'name': name,
      'platform': platform,
      'userId': userId,
    };
  }
}
