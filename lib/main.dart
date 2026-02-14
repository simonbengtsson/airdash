import 'package:airdash/interface/themes.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'interface/setup_screen.dart';
import 'interface/window_manager.dart';
import 'reporting/sentry_setup.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SentryFlutter.init(
    (options) async {
      await SentryManager.setup(options);
    },
    appRunner: () {
      AppWindowManager().setupWindow();
      return runApp(const ProviderScope(child: App()));
    },
  );
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: ThemeMode.system,
      home: const SetupScreen(),
    );
  }
}
