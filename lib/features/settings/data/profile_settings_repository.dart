import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final profileSettingsRepositoryProvider = Provider<ProfileSettingsRepository>((
  ref,
) {
  return ProfileSettingsRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
  );
});

final accountSettingsProvider = StreamProvider<AccountSettings>((ref) {
  return ref.watch(profileSettingsRepositoryProvider).watchAccount();
});

final goalSettingsProvider = StreamProvider<GoalSettings>((ref) {
  return ref.watch(profileSettingsRepositoryProvider).watchGoals();
});

final aiPersonalizationProvider = StreamProvider<bool>((ref) {
  return ref.watch(profileSettingsRepositoryProvider).watchAiPersonalization();
});

class AccountSettings {
  const AccountSettings({
    required this.displayName,
    required this.country,
    required this.timezone,
    required this.unitSystem,
  });
  final String displayName;
  final String country;
  final String timezone;
  final String unitSystem;
}

class GoalSettings {
  const GoalSettings({
    required this.energyKcal,
    required this.proteinG,
    required this.fiberG,
    required this.waterMl,
  });
  final double energyKcal;
  final double proteinG;
  final double fiberG;
  final double waterMl;
}

class ProfileSettingsRepository {
  const ProfileSettingsRepository(this.auth, this.firestore);
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  String get uid {
    final value = auth.currentUser?.uid;
    if (value == null) throw StateError('No authenticated user.');
    return value;
  }

  Stream<AccountSettings> watchAccount() =>
      firestore.collection('users').doc(uid).snapshots().map((snapshot) {
        final data = snapshot.data() ?? const <String, dynamic>{};
        return AccountSettings(
          displayName: data['displayName'] as String? ?? '',
          country: data['country'] as String? ?? '',
          timezone: data['timezone'] as String? ?? 'UTC',
          unitSystem: data['unitSystem'] as String? ?? 'metric',
        );
      });

  Stream<GoalSettings> watchGoals() =>
      firestore.doc('users/$uid/private/goals').snapshots().map((snapshot) {
        final data = snapshot.data() ?? const <String, dynamic>{};
        return GoalSettings(
          energyKcal: (data['energyKcal'] as num?)?.toDouble() ?? 2000,
          proteinG: (data['proteinG'] as num?)?.toDouble() ?? 80,
          fiberG: (data['fiberG'] as num?)?.toDouble() ?? 30,
          waterMl: (data['waterMl'] as num?)?.toDouble() ?? 2500,
        );
      });

  Stream<bool> watchAiPersonalization() => firestore
      .doc('users/$uid/private/ai')
      .snapshots()
      .map(
        (snapshot) =>
            snapshot.data()?['personalizationEnabled'] as bool? ?? true,
      );

  Future<void> saveAccount({
    required String displayName,
    required String country,
    required String timezone,
  }) async {
    await firestore.collection('users').doc(uid).update({
      'displayName': displayName.trim(),
      'country': country.trim().toUpperCase(),
      'timezone': timezone.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await auth.currentUser?.updateDisplayName(displayName.trim());
  }

  Future<void> saveGoals(GoalSettings goals) async {
    final reference = firestore.doc('users/$uid/private/goals');
    await firestore.runTransaction((transaction) async {
      final current = await transaction.get(reference);
      transaction.set(reference, {
        'primaryGoal': current.data()?['primaryGoal'] ?? 'eat_healthier',
        'energyKcal': goals.energyKcal,
        'proteinG': goals.proteinG,
        'fiberG': goals.fiberG,
        'waterMl': goals.waterMl,
        'source': 'user',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> setAiPersonalization(bool enabled) =>
      firestore.doc('users/$uid/private/ai').set({
        'personalizationEnabled': enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      });
}
