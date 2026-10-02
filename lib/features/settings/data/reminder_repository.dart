import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum ReminderType { expiry, lowStock, hydration, meal, weeklySummary }

final reminderRepositoryProvider = Provider<ReminderRepository>((ref) {
  return ReminderRepository(FirebaseAuth.instance, FirebaseFirestore.instance);
});

final reminderPreferencesProvider = StreamProvider<ReminderPreferences>((ref) {
  return ref.watch(reminderRepositoryProvider).watch();
});

class ReminderPreferences {
  const ReminderPreferences({
    required this.expiry,
    required this.lowStock,
    required this.hydration,
    required this.meal,
    required this.weeklySummary,
    required this.wakeTime,
    required this.sleepTime,
    required this.breakfastTime,
    required this.lunchTime,
    required this.dinnerTime,
  });

  const ReminderPreferences.defaults()
    : expiry = true,
      lowStock = true,
      hydration = false,
      meal = false,
      weeklySummary = true,
      wakeTime = '07:00',
      sleepTime = '23:00',
      breakfastTime = '09:00',
      lunchTime = '14:00',
      dinnerTime = '20:00';

  final bool expiry;
  final bool lowStock;
  final bool hydration;
  final bool meal;
  final bool weeklySummary;
  final String wakeTime;
  final String sleepTime;
  final String breakfastTime;
  final String lunchTime;
  final String dinnerTime;

  factory ReminderPreferences.fromMap(Map<String, dynamic>? data) =>
      ReminderPreferences(
        expiry: data?['expiryAlertsEnabled'] as bool? ?? true,
        lowStock: data?['lowStockAlertsEnabled'] as bool? ?? true,
        hydration: data?['hydrationRemindersEnabled'] as bool? ?? false,
        meal: data?['mealRemindersEnabled'] as bool? ?? false,
        weeklySummary: data?['weeklySummaryEnabled'] as bool? ?? true,
        wakeTime: data?['wakeTime'] as String? ?? '07:00',
        sleepTime: data?['sleepTime'] as String? ?? '23:00',
        breakfastTime: data?['breakfastTime'] as String? ?? '09:00',
        lunchTime: data?['lunchTime'] as String? ?? '14:00',
        dinnerTime: data?['dinnerTime'] as String? ?? '20:00',
      );
}

class ReminderRepository {
  const ReminderRepository(this.auth, this.firestore);
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  DocumentReference<Map<String, dynamic>> get reference {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw StateError('No authenticated user.');
    return firestore.doc('users/$uid/private/routine');
  }

  Stream<ReminderPreferences> watch() => reference.snapshots().map(
    (snapshot) => ReminderPreferences.fromMap(snapshot.data()),
  );

  Future<void> setEnabled(ReminderType type, bool enabled) async {
    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final current = snapshot.data() ?? const <String, dynamic>{};
      transaction.set(reference, {
        'wakeTime': current['wakeTime'] ?? '07:00',
        'sleepTime': current['sleepTime'] ?? '23:00',
        'preferredGroceryDay': current['preferredGroceryDay'] ?? 'Saturday',
        'breakfastTime': current['breakfastTime'] ?? '09:00',
        'lunchTime': current['lunchTime'] ?? '14:00',
        'dinnerTime': current['dinnerTime'] ?? '20:00',
        'expiryAlertsEnabled': current['expiryAlertsEnabled'] ?? true,
        'lowStockAlertsEnabled': current['lowStockAlertsEnabled'] ?? true,
        'hydrationRemindersEnabled':
            current['hydrationRemindersEnabled'] ?? false,
        'mealRemindersEnabled': current['mealRemindersEnabled'] ?? false,
        'weeklySummaryEnabled': current['weeklySummaryEnabled'] ?? true,
        _field(type): enabled,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> updateSchedule({
    required String wakeTime,
    required String sleepTime,
    required String breakfastTime,
    required String lunchTime,
    required String dinnerTime,
  }) async {
    final values = [wakeTime, sleepTime, breakfastTime, lunchTime, dinnerTime];
    final validTime = RegExp(r'^([01]\d|2[0-3]):[0-5]\d$');
    if (values.any((value) => !validTime.hasMatch(value))) {
      throw const FormatException('Times must use 24-hour HH:mm format.');
    }
    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(reference);
      final current = snapshot.data() ?? const <String, dynamic>{};
      transaction.set(reference, {
        'wakeTime': wakeTime,
        'sleepTime': sleepTime,
        'breakfastTime': breakfastTime,
        'lunchTime': lunchTime,
        'dinnerTime': dinnerTime,
        'preferredGroceryDay': current['preferredGroceryDay'] ?? 'Saturday',
        'expiryAlertsEnabled': current['expiryAlertsEnabled'] ?? true,
        'lowStockAlertsEnabled': current['lowStockAlertsEnabled'] ?? true,
        'hydrationRemindersEnabled':
            current['hydrationRemindersEnabled'] ?? false,
        'mealRemindersEnabled': current['mealRemindersEnabled'] ?? false,
        'weeklySummaryEnabled': current['weeklySummaryEnabled'] ?? true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  String _field(ReminderType type) => switch (type) {
    ReminderType.expiry => 'expiryAlertsEnabled',
    ReminderType.lowStock => 'lowStockAlertsEnabled',
    ReminderType.hydration => 'hydrationRemindersEnabled',
    ReminderType.meal => 'mealRemindersEnabled',
    ReminderType.weeklySummary => 'weeklySummaryEnabled',
  };
}
