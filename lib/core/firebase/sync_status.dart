import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum FirestoreSyncStatus { synced, syncing, cached }

final firestoreSyncStatusProvider = StreamProvider<FirestoreSyncStatus>((ref) {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return Stream.value(FirestoreSyncStatus.synced);
  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .snapshots(includeMetadataChanges: true)
      .map((snapshot) {
        if (snapshot.metadata.hasPendingWrites) {
          return FirestoreSyncStatus.syncing;
        }
        if (snapshot.metadata.isFromCache) {
          return FirestoreSyncStatus.cached;
        }
        return FirestoreSyncStatus.synced;
      })
      .distinct();
});
