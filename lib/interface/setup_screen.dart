import 'package:firedart/auth/firebase_auth.dart';
import 'package:firedart/firestore/firestore.dart';
import 'package:flutter/material.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import '../model/user.dart';
import '../reporting/analytics_logger.dart';
import '../reporting/error_logger.dart';
import '../reporting/logger.dart';
import '../shared_preferences_store.dart';
import 'home.dart';

class SetupScreen extends StatefulWidget {
  const SetupScreen({Key? key}) : super(key: key);

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  var loadingText = '';
  var showTryAgain = false;

  @override
  void initState() {
    initFirebase();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        body: Center(
            child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(loadingText),
        if (showTryAgain)
          TextButton(
            onPressed: () async {
              setState(() {
                showTryAgain = false;
                loadingText = 'Setting up';
              });
              await Future.delayed(const Duration(seconds: 1));
              await trySignIn();
            },
            child: const Text('Try Again'),
          ),
      ],
    )));
  }

  initFirebase() async {
    var prefs = await SharedPreferences.getInstance();
    FirebaseAuth.initialize(
        Config.firebaseApiKey, SharedPreferenceStore(prefs));
    Firestore.initialize(Config.firebaseProjectId);
    await trySignIn();
  }

  clear() async {
    try {
      await FirebaseAuth.instance.deleteAccount();
      FirebaseAuth.instance.signOut();
      // ignore: empty_catches
    } catch (err) {}
    var prefs = await SharedPreferences.getInstance();

    prefs.remove('currentUser');
  }

  trySignIn() async {
    var prefs = await SharedPreferences.getInstance();
    var userState = UserState(prefs);
    normalizeAuthState(prefs, userState);

    var storedUser = userState.getCurrentUser();
    if (storedUser != null) {
      await userState.saveUser(storedUser);
      navigateToHome();
      logger('SETUP: Already sign in, showing home');
    } else {
      logger('SETUP: Starting anonymous user sign in');
      setState(() {
        loadingText = 'Setting up';
      });
      try {
        var firebaseUser = await FirebaseAuth.instance
            .signInAnonymously()
            .timeout(const Duration(seconds: 10));
        var user = User.create(firebaseUser.id);
        await userState.saveUser(user);
        Sentry.configureScope((scope) {
          scope.setUser(SentryUser(id: firebaseUser.id));
        });
        navigateToHome();
        logger('SETUP: Anonymous user signed in, showing home');
      } catch (error, stack) {
        ErrorLogger.logStackError('failedAnonSignIn', error, stack);
        setState(() {
          showTryAgain = true;
          loadingText = 'Setup failed. Check your internet connection.';
        });
      }
    }
  }

  normalizeAuthState(SharedPreferences prefs, UserState userState) {
    var storedUser = userState.getCurrentUser();

    if (storedUser == null && FirebaseAuth.instance.isSignedIn) {
      var firebaseUserId = FirebaseAuth.instance.userId;
      if (firebaseUserId == 'TP8nXzD9lUaxJYZlnhDSuZdlqWE3') {
        logger('Demo user signed out');
      } else {
        ErrorLogger.logSimpleError('missingStoredUser',
            {'firebase': firebaseUserId, 'stored': storedUser?.id ?? '(null)'});
      }
      FirebaseAuth.instance.signOut();
    }

    if (storedUser != null && !FirebaseAuth.instance.isSignedIn) {
      ErrorLogger.logSimpleError('missingFirebaseUser', {
        'stored': storedUser.id,
      });
      prefs.remove('currentUser');
      storedUser = null;
    }
  }

  navigateToHome() {
    var route = PageRouteBuilder(
      pageBuilder: (context, animation1, animation2) => const MyHomePage(),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
    );
    if (mounted) {
      Navigator.of(context).pushReplacement(route);
      AnalyticsEvent.appLaunched.log();
    }
  }
}
