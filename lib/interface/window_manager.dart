import 'dart:io';

import 'package:flutter/material.dart' hide MenuItem;
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import '../config.dart';
import '../helpers.dart';
import '../reporting/logger.dart';

class WindowManager {
  setupWindow() async {
    if (!isDesktop()) {
      return;
    }
    await windowManager.ensureInitialized();

    windowManager.waitUntilReadyToShow().then((_) async {
      await windowManager.setSize(const Size(500, 700));
      await windowManager.setMinimumSize(const Size(420, 420));
      if (Config.enableDesktopTray) {
        await _setupTray();
        await windowManager.setTitleBarStyle(TitleBarStyle.hidden,
            windowButtonVisibility: false);
        await windowManager.setAlwaysOnTop(true);
        await windowManager.setSize(const Size(400, 400));
        await windowManager.setResizable(false);
        if (Platform.isMacOS) {
          await windowManager.setMovable(false);
        }
        await windowManager.setSkipTaskbar(true);
        var bounds = await trayManager.getBounds();
        await windowManager.setPosition(bounds!.topLeft);
      }
      await windowManager.show();
    });
  }

  _setupTray() async {
    await trayManager.setIcon(
      Platform.isWindows ? 'images/tray_icon.ico' : 'images/tray_icon.png',
    );
    List<MenuItem> items = [
      MenuItem(
        key: 'exit_app',
        label: 'Exit App',
      ),
    ];
    await trayManager.setContextMenu(Menu(items: items));
    await trayManager.setToolTip('AirDash');
    logger('MAIN: Finished setting up tray ${items.length}');
  }
}
