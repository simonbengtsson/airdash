import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../helpers.dart';
import '../model/value_store.dart';
import '../reporting/logger.dart';

class AppWindowManager {
  Future<void> setupWindow() async {
    if (!isDesktop()) {
      return;
    }

    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow();

    var prefs = await SharedPreferences.getInstance();
    var enabled = ValueStore(prefs).isTrayModeEnabled();

    if (Platform.isMacOS) {
      await windowManager.setMovable(!enabled);
    }
    await windowManager.setSkipTaskbar(enabled);
    await windowManager.setResizable(!enabled);
    await windowManager.setMinimumSize(const Size(420, 420));
    await windowManager.setAlwaysOnTop(enabled);
    await windowManager.setSize(const Size(500, 700));

    if (!enabled) {
      await trayManager.destroy();
      await windowManager.setTitleBarStyle(TitleBarStyle.normal,
          windowButtonVisibility: true);
      await windowManager.show();
    } else {
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden,
          windowButtonVisibility: false);
      await _setupTray();
      await windowManager.hide();
    }

    print('Window shown');
  }

  Future<void> _setupTray() async {
    await trayManager.setIcon(
      Platform.isWindows ? 'assets/tray_icon.ico' : 'assets/tray_icon.png',
      isTemplate: true,
    );
    List<MenuItem> items = [
      MenuItem(
        key: 'exit_app',
        label: 'Exit App',
      ),
    ];
    await trayManager.setContextMenu(Menu(items: items));
    await trayManager.setToolTip('AirDash');

    await Future<void>.delayed(const Duration(milliseconds: 500));
    var bounds = await trayManager.getBounds();
    await windowManager.setPosition(bounds!.topLeft);

    logger('MAIN: Finished setting up tray ${items.length}');
  }
}
