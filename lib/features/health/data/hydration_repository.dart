import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final hydrationRepositoryProvider = Provider<HydrationRepository>((ref) {
  return HydrationRepository(FirebaseAuth.instance, FirebaseFirestore.instance);
});

final hydrationLogsProvider = StreamProvider<List<HydrationLog>>((ref) {
  return ref.watch(hydrationRepositoryProvider).watchRecent();
});

class HydrationLog {
  const HydrationLog({
    required this.id,
    required this.amountMl,
    required this.loggedAt,
  });

  final String id;
  final double amountMl;
  final DateTime loggedAt;

  factory HydrationLog.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    return HydrationLog(
      id: document.id,
      amountMl: (data['amountMl'] as num?)?.toDouble() ?? 0,
      loggedAt: (data['loggedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }
}

class HydrationRepository {
  const HydrationRepository(this.auth, this.firestore);

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  CollectionReference<Map<String, dynamic>> get collection {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw StateError('No authenticated user.');
    return firestore.collection('users').doc(uid).collection('hydrationLogs');
  }

  Stream<List<HydrationLog>> watchRecent() => collection
      .orderBy('loggedAt', descending: true)
      .limit(200)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(HydrationLog.fromDocument).toList());

  Future<void> add(double amountMl) {
    if (amountMl <= 0 || amountMl > 5000) {
      throw ArgumentError.value(amountMl, 'amountMl');
    }
    return collection.add({
      'amountMl': amountMl,
      'loggedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> delete(String id) => collection.doc(id).delete();
}
