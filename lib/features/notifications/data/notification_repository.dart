import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  return NotificationRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
  );
});

final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  return ref.watch(notificationRepositoryProvider).watch();
});

final unreadNotificationCountProvider = Provider<int>((ref) {
  return ref
      .watch(notificationsProvider)
      .maybeWhen(
        data: (values) =>
            values.where((value) => !value.isRead && value.isVisible).length,
        orElse: () => 0,
      );
});

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.route,
    required this.status,
    required this.createdAt,
    required this.readAt,
  });

  final String id;
  final String type;
  final String title;
  final String body;
  final String route;
  final String status;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;
  bool get isVisible => status == 'sent';

  factory AppNotification.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    return AppNotification(
      id: document.id,
      type: data['type'] as String? ?? 'general',
      title: data['title'] as String? ?? 'TUM.me',
      body: data['body'] as String? ?? '',
      route: data['route'] as String? ?? '/home/today',
      status: data['status'] as String? ?? 'sending',
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      readAt: (data['readAt'] as Timestamp?)?.toDate(),
    );
  }
}

class NotificationRepository {
  const NotificationRepository(this.auth, this.firestore);
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  CollectionReference<Map<String, dynamic>> get collection {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw StateError('No authenticated user.');
    return firestore.collection('users').doc(uid).collection('notifications');
  }

  Stream<List<AppNotification>> watch() => collection
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map(AppNotification.fromDocument).toList(),
      );

  Future<void> markRead(String id) =>
      collection.doc(id).update({'readAt': FieldValue.serverTimestamp()});
}
