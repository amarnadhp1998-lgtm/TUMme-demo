import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final messagingServiceProvider = Provider<MessagingService>((ref) {
  if (kIsWeb) return MessagingService.disabled();
  final service = MessagingService(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
    FirebaseMessaging.instance,
    FirebaseFunctions.instanceFor(region: 'asia-south1'),
  );
  ref.onDispose(service.dispose);
  return service;
});

final foregroundMessagesProvider = StreamProvider<RemoteMessage>((ref) {
  if (kIsWeb) return const Stream.empty();
  return FirebaseMessaging.onMessage;
});

class MessagingService {
  MessagingService(this.auth, this.firestore, this.messaging, this.functions) {
    _tokenSubscription = messaging!.onTokenRefresh.listen(_storeToken);
    _authSubscription = auth!.userChanges().listen((user) {
      if (user != null) unawaited(restoreRegistrationIfAuthorized());
    });
  }

  MessagingService.disabled()
    : auth = null,
      firestore = null,
      messaging = null,
      functions = null;

  final FirebaseAuth? auth;
  final FirebaseFirestore? firestore;
  final FirebaseMessaging? messaging;
  final FirebaseFunctions? functions;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<User?>? _authSubscription;

  Future<bool> enableForReminders() async {
    final instance = messaging;
    if (instance == null || !await instance.isSupported()) return false;
    final settings = await instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
    final allowed =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
    if (!allowed) return false;
    await _registerCurrentToken();
    return true;
  }

  Future<void> restoreRegistrationIfAuthorized() async {
    final instance = messaging;
    if (instance == null || !await instance.isSupported()) return;
    final settings = await instance.getNotificationSettings();
    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      await _registerCurrentToken();
    }
  }

  Future<void> sendTestNotification() async {
    final callableFunctions = functions;
    if (callableFunctions == null) {
      throw UnsupportedError('Push notifications are unavailable on web.');
    }
    final enabled = await enableForReminders();
    if (!enabled) throw StateError('Notification permission was not granted.');
    await callableFunctions.httpsCallable('sendTestNotification').call<void>();
  }

  Future<void> _registerCurrentToken() async {
    final token = await messaging?.getToken();
    if (token != null && token.isNotEmpty) await _storeToken(token);
  }

  Future<void> _storeToken(String token) async {
    final uid = auth?.currentUser?.uid;
    if (uid == null) return;
    final id = Uri.encodeComponent(token);
    final reference = firestore!.doc('users/$uid/notificationTokens/$id');
    final existing = await reference.get();
    await reference.set({
      'token': token,
      'platform': _platform,
      'enabled': true,
      'createdAt':
          existing.data()?['createdAt'] ?? FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  String get _platform {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  void dispose() {
    _tokenSubscription?.cancel();
    _authSubscription?.cancel();
  }
}
