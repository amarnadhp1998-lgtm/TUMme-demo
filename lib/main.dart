import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/firebase/firebase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final configuration = FirebaseConfiguration.fromDefines();
  if (!configuration.isComplete) {
    runApp(ConfigurationMissingApp(configuration.missingFields));
    return;
  }
  await Firebase.initializeApp(options: configuration.options);
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
  );
  if (kIsWeb) {
    const siteKey = String.fromEnvironment('FIREBASE_APP_CHECK_WEB_SITE_KEY');
    if (siteKey.isNotEmpty) {
      await FirebaseAppCheck.instance.activate(
        providerWeb: ReCaptchaV3Provider(siteKey),
      );
    }
  } else {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: configuration.isDevelopment
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: configuration.isDevelopment
          ? const AppleDebugProvider()
          : const AppleAppAttestProvider(),
    );
  }
  // The Pages demo has no Analytics measurement ID. Avoid initializing the
  // web Analytics SDK in stage builds, where loading it can delay first paint.
  if (!kIsWeb || configuration.isProduction) {
    await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(
      configuration.isProduction,
    );
  }
  final crashlyticsEnabled = !kIsWeb && configuration.isProduction;
  if (!kIsWeb) {
    await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      configuration.isProduction,
    );
  }
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    if (crashlyticsEnabled) {
      unawaited(FirebaseCrashlytics.instance.recordFlutterFatalError(details));
    }
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    if (crashlyticsEnabled) {
      unawaited(
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true),
      );
    }
    return true;
  };
  runApp(ProviderScope(child: TUMmeApp(configuration: configuration)));
}
