import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

enum AppEnvironment { dev, stage, prod }

class FirebaseConfiguration {
  const FirebaseConfiguration({
    required this.environment,
    required this.apiKey,
    required this.appId,
    required this.messagingSenderId,
    required this.projectId,
    required this.authDomain,
    required this.storageBucket,
    required this.measurementId,
    required this.iosBundleId,
    required this.androidClientId,
    required this.iosClientId,
  });

  final AppEnvironment environment;
  final String apiKey;
  final String appId;
  final String messagingSenderId;
  final String projectId;
  final String authDomain;
  final String storageBucket;
  final String measurementId;
  final String iosBundleId;
  final String androidClientId;
  final String iosClientId;

  static FirebaseConfiguration fromDefines() {
    const name = String.fromEnvironment('APP_ENV', defaultValue: 'dev');
    return FirebaseConfiguration(
      environment: AppEnvironment.values.firstWhere(
        (value) => value.name == name,
        orElse: () => AppEnvironment.dev,
      ),
      apiKey: kIsWeb
          ? const String.fromEnvironment(
              'FIREBASE_WEB_API_KEY',
              defaultValue: String.fromEnvironment('FIREBASE_API_KEY'),
            )
          : defaultTargetPlatform == TargetPlatform.iOS
          ? const String.fromEnvironment(
              'FIREBASE_IOS_API_KEY',
              defaultValue: String.fromEnvironment('FIREBASE_API_KEY'),
            )
          : const String.fromEnvironment(
              'FIREBASE_ANDROID_API_KEY',
              defaultValue: String.fromEnvironment('FIREBASE_API_KEY'),
            ),
      appId: kIsWeb
          ? const String.fromEnvironment('FIREBASE_WEB_APP_ID')
          : defaultTargetPlatform == TargetPlatform.iOS
          ? const String.fromEnvironment('FIREBASE_IOS_APP_ID')
          : const String.fromEnvironment('FIREBASE_ANDROID_APP_ID'),
      messagingSenderId: kIsWeb
          ? const String.fromEnvironment(
              'FIREBASE_WEB_MESSAGING_SENDER_ID',
              defaultValue: String.fromEnvironment('FIREBASE_SENDER_ID'),
            )
          : const String.fromEnvironment('FIREBASE_SENDER_ID'),
      projectId: kIsWeb
          ? const String.fromEnvironment(
              'FIREBASE_WEB_PROJECT_ID',
              defaultValue: String.fromEnvironment('FIREBASE_PROJECT_ID'),
            )
          : const String.fromEnvironment('FIREBASE_PROJECT_ID'),
      authDomain: const String.fromEnvironment('FIREBASE_WEB_AUTH_DOMAIN'),
      storageBucket: const String.fromEnvironment(
        'FIREBASE_WEB_STORAGE_BUCKET',
      ),
      measurementId: const String.fromEnvironment(
        'FIREBASE_WEB_MEASUREMENT_ID',
      ),
      iosBundleId: const String.fromEnvironment(
        'FIREBASE_IOS_BUNDLE_ID',
        defaultValue: 'me.tum.app',
      ),
      androidClientId: const String.fromEnvironment(
        'FIREBASE_ANDROID_CLIENT_ID',
      ),
      iosClientId: const String.fromEnvironment('FIREBASE_IOS_CLIENT_ID'),
    );
  }

  bool get isDevelopment => environment == AppEnvironment.dev;
  bool get isProduction => environment == AppEnvironment.prod;
  List<String> get missingFields => [
    if (apiKey.isEmpty)
      kIsWeb
          ? 'FIREBASE_WEB_API_KEY'
          : defaultTargetPlatform == TargetPlatform.iOS
          ? 'FIREBASE_IOS_API_KEY'
          : 'FIREBASE_ANDROID_API_KEY',
    if (appId.isEmpty)
      kIsWeb
          ? 'FIREBASE_WEB_APP_ID'
          : defaultTargetPlatform == TargetPlatform.iOS
          ? 'FIREBASE_IOS_APP_ID'
          : 'FIREBASE_ANDROID_APP_ID',
    if (messagingSenderId.isEmpty)
      kIsWeb ? 'FIREBASE_WEB_MESSAGING_SENDER_ID' : 'FIREBASE_SENDER_ID',
    if (projectId.isEmpty)
      kIsWeb ? 'FIREBASE_WEB_PROJECT_ID' : 'FIREBASE_PROJECT_ID',
    if (kIsWeb && authDomain.isEmpty) 'FIREBASE_WEB_AUTH_DOMAIN',
  ];
  bool get isComplete => missingFields.isEmpty;

  FirebaseOptions get options => FirebaseOptions(
    apiKey: apiKey,
    appId: appId,
    messagingSenderId: messagingSenderId,
    projectId: projectId,
    authDomain: kIsWeb && authDomain.isNotEmpty ? authDomain : null,
    storageBucket: kIsWeb && storageBucket.isNotEmpty ? storageBucket : null,
    measurementId: kIsWeb && measurementId.isNotEmpty ? measurementId : null,
    iosBundleId: defaultTargetPlatform == TargetPlatform.iOS
        ? iosBundleId
        : null,
    androidClientId: androidClientId.isEmpty ? null : androidClientId,
    iosClientId: iosClientId.isEmpty ? null : iosClientId,
  );
}

class ConfigurationMissingApp extends StatelessWidget {
  const ConfigurationMissingApp(this.missingFields, {super.key});
  final List<String> missingFields;

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.settings_suggest_outlined, size: 48),
              const SizedBox(height: 16),
              const Text('TUM.me needs Firebase configuration'),
              const SizedBox(height: 8),
              Text('Missing: ${missingFields.join(', ')}'),
            ],
          ),
        ),
      ),
    ),
  );
}
