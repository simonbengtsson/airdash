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
  const App({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    var primaryColor = const Color.fromRGBO(150, 150, 250, 1);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: primaryColor),
          useMaterial3: true),
      home: const SetupScreen(),
    );
  }
}
