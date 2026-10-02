import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final onboardingRepositoryProvider = Provider<OnboardingRepository>((ref) {
  return OnboardingRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
  );
});

class OnboardingRepository {
  const OnboardingRepository(this.auth, this.firestore);
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  String get uid {
    final value = auth.currentUser?.uid;
    if (value == null) throw StateError('No authenticated user.');
    return value;
  }

  Future<void> saveProfile({
    required String displayName,
    required String country,
    required String timezone,
    required String dateOfBirth,
    required String sex,
    required double heightCm,
    required double weightKg,
    required String activityLevel,
  }) async {
    final batch = firestore.batch();
    batch.update(firestore.collection('users').doc(uid), {
      'displayName': displayName.trim(),
      'country': country,
      'timezone': timezone,
      'unitSystem': 'metric',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    batch.set(firestore.doc('users/$uid/private/profile'), {
      'dateOfBirth': dateOfBirth,
      'sexForReferenceCalculation': sex,
      'heightCm': heightCm,
      'weightKg': weightKg,
      'activityLevel': activityLevel,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    await auth.currentUser?.updateDisplayName(displayName.trim());
  }

  Future<void> savePrivate(String document, Map<String, Object?> data) =>
      firestore.doc('users/$uid/private/$document').set({
        ...data,
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> finish() => firestore.collection('users').doc(uid).update({
    'onboardingCompleted': true,
    'updatedAt': FieldValue.serverTimestamp(),
  });
}
