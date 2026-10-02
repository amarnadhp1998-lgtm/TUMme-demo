import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final healthAggregateRepositoryProvider = Provider<HealthAggregateRepository>((
  ref,
) {
  return HealthAggregateRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
  );
});

final dailyNutritionProvider = StreamProvider<List<DailyNutritionAggregate>>((
  ref,
) {
  return ref.watch(healthAggregateRepositoryProvider).watchDaily();
});

class DailyNutritionAggregate {
  const DailyNutritionAggregate({
    required this.date,
    required this.energyKcal,
    required this.proteinG,
    required this.fiberG,
    required this.waterMl,
    required this.plantFoodIds,
  });

  final DateTime date;
  final double energyKcal;
  final double proteinG;
  final double fiberG;
  final double waterMl;
  final Set<String> plantFoodIds;

  factory DailyNutritionAggregate.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    return DailyNutritionAggregate(
      date: DateTime.tryParse(document.id) ?? DateTime(1970),
      energyKcal: (data['energyKcal'] as num?)?.toDouble() ?? 0,
      proteinG: (data['proteinG'] as num?)?.toDouble() ?? 0,
      fiberG: (data['fiberG'] as num?)?.toDouble() ?? 0,
      waterMl: (data['waterMl'] as num?)?.toDouble() ?? 0,
      plantFoodIds: Set<String>.from(
        (data['uniquePlantFoodIds'] as List<dynamic>? ?? const [])
            .whereType<String>(),
      ),
    );
  }
}

class HealthAggregateRepository {
  const HealthAggregateRepository(this.auth, this.firestore);

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  Stream<List<DailyNutritionAggregate>> watchDaily() {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw StateError('No authenticated user.');
    return firestore
        .collection('users')
        .doc(uid)
        .collection('nutritionDaily')
        .orderBy(FieldPath.documentId, descending: true)
        .limit(31)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(DailyNutritionAggregate.fromDocument).toList(),
        );
  }
}
