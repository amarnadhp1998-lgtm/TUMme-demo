import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_capabilities.dart';
import '../domain/food_catalog.dart';

final mealRepositoryProvider = Provider<MealRepository>((ref) {
  return MealRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
    FirebaseFunctions.instanceFor(region: 'asia-south1'),
  );
});

final mealsProvider = StreamProvider<List<MealLog>>((ref) {
  return ref.watch(mealRepositoryProvider).watchMeals();
});

final dailyNutritionProvider =
    Provider.family<AsyncValue<DailyNutrition>, DateTime>((ref, date) {
      return ref.watch(mealsProvider).whenData((meals) {
        final selected =
            meals.where((meal) => _sameLocalDay(meal.consumedAt, date)).toList()
              ..sort((a, b) => a.consumedAt.compareTo(b.consumedAt));
        return DailyNutrition.fromMeals(date, selected);
      });
    });

class DailyNutrition {
  const DailyNutrition({
    required this.date,
    required this.meals,
    required this.energyKcal,
    required this.proteinG,
    required this.fiberG,
  });

  final DateTime date;
  final List<MealLog> meals;
  final double energyKcal;
  final double proteinG;
  final double fiberG;

  factory DailyNutrition.fromMeals(DateTime date, List<MealLog> meals) {
    return DailyNutrition(
      date: DateTime(date.year, date.month, date.day),
      meals: List.unmodifiable(meals),
      energyKcal: meals.fold(0.0, (total, meal) => total + meal.energyKcal),
      proteinG: meals.fold(0.0, (total, meal) => total + meal.proteinG),
      fiberG: meals.fold(0.0, (total, meal) => total + meal.fiberG),
    );
  }
}

class MealLog {
  const MealLog({
    required this.id,
    required this.mealType,
    required this.description,
    required this.consumedAt,
    required this.energyKcal,
    required this.proteinG,
    required this.fiberG,
    required this.items,
  });

  final String id;
  final String mealType;
  final String description;
  final DateTime consumedAt;
  final double energyKcal;
  final double proteinG;
  final double fiberG;
  final List<MealLineSnapshot> items;

  factory MealLog.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    final totals = data['totals'] as Map<String, dynamic>? ?? const {};
    return MealLog(
      id: document.id,
      mealType: data['mealType'] as String? ?? 'snack',
      description: data['originalText'] as String? ?? '',
      consumedAt:
          (data['consumedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      energyKcal: (totals['energyKcal'] as num?)?.toDouble() ?? 0,
      proteinG: (totals['proteinG'] as num?)?.toDouble() ?? 0,
      fiberG: (totals['fiberG'] as num?)?.toDouble() ?? 0,
      items: (data['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MealLineSnapshot.fromMap)
          .toList(),
    );
  }
}

class MealRepository {
  const MealRepository(this.auth, this.firestore, this.functions);
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;

  CollectionReference<Map<String, dynamic>> get collection {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw StateError('No authenticated user.');
    return firestore.collection('users').doc(uid).collection('meals');
  }

  Stream<List<MealLog>> watchMeals() => collection
      .orderBy('consumedAt', descending: true)
      .limit(500)
      .snapshots()
      .map((snapshot) => snapshot.docs.map(MealLog.fromDocument).toList());

  Future<void> add({
    required String mealType,
    required String description,
    required DateTime consumedAt,
    required double energyKcal,
    required double proteinG,
    required double fiberG,
  }) => collection.add({
    'mealType': mealType,
    'consumedAt': Timestamp.fromDate(consumedAt),
    'source': 'manual',
    'originalText': description.trim(),
    'items': <Map<String, dynamic>>[],
    'totals': {
      'energyKcal': energyKcal,
      'proteinG': proteinG,
      'fiberG': fiberG,
    },
    'calculationVersion': 'manual-v1',
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> delete(String id) async {
    if (!AppCapabilities.mealDeletion) {
      throw UnsupportedError('Meal deletion is unavailable in the free demo.');
    }
    await functions.httpsCallable('deleteMeal').call<void>({'mealId': id});
  }

  Future<void> duplicate(MealLog meal) => collection.add({
    'mealType': meal.mealType,
    'consumedAt': Timestamp.fromDate(DateTime.now()),
    'source': 'duplicate',
    'originalText': meal.description,
    'items': [for (final item in meal.items) item.toMap()],
    'totals': {
      'energyKcal': meal.energyKcal,
      'proteinG': meal.proteinG,
      'fiberG': meal.fiberG,
    },
    'calculationVersion': meal.items.isEmpty ? 'manual-v1' : 'nutrition-v1',
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> addFromCatalog({
    required String mealType,
    required DateTime consumedAt,
    required List<CatalogMealLine> lines,
  }) {
    final totals = lines.fold<NutritionSnapshot>(
      NutritionSnapshot.zero,
      (total, line) => total + line.nutrition,
    );
    return collection.add({
      'mealType': mealType,
      'consumedAt': Timestamp.fromDate(consumedAt),
      'source': 'search',
      'originalText': lines.map((line) => line.food.name).join(', '),
      'items': [
        for (var index = 0; index < lines.length; index++)
          lines[index].toMap(lineId: '${lines[index].food.id}-$index'),
      ],
      'totals': {
        'energyKcal': totals.energyKcal,
        'proteinG': totals.proteinG,
        'fiberG': totals.fiberG,
      },
      'calculationVersion': 'nutrition-v1',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}

class MealLineSnapshot {
  const MealLineSnapshot({
    required this.lineId,
    required this.foodId,
    required this.displayName,
    required this.quantity,
    required this.unit,
    required this.grams,
    required this.energyKcal,
    required this.proteinG,
    required this.fiberG,
    required this.inventoryStatus,
  });

  final String lineId;
  final String? foodId;
  final String displayName;
  final double quantity;
  final String unit;
  final double grams;
  final double energyKcal;
  final double proteinG;
  final double fiberG;
  final String inventoryStatus;

  factory MealLineSnapshot.fromMap(Map<String, dynamic> data) {
    final nutrition =
        data['nutritionSnapshot'] as Map<String, dynamic>? ?? const {};
    return MealLineSnapshot(
      lineId:
          (data['lineId'] as String?) ?? (data['foodId'] as String?) ?? 'line',
      foodId: data['foodId'] as String?,
      displayName: data['displayName'] as String? ?? 'Food',
      quantity: (data['quantity'] as num?)?.toDouble() ?? 0,
      unit: data['unit'] as String? ?? '',
      grams: (data['grams'] as num?)?.toDouble() ?? 0,
      energyKcal: (nutrition['energyKcal'] as num?)?.toDouble() ?? 0,
      proteinG: (nutrition['proteinG'] as num?)?.toDouble() ?? 0,
      fiberG: (nutrition['fiberG'] as num?)?.toDouble() ?? 0,
      inventoryStatus: data['inventoryStatus'] as String? ?? 'not_matched',
    );
  }

  Map<String, dynamic> toMap() => {
    'lineId': lineId,
    if (foodId != null) 'foodId': foodId,
    'displayName': displayName,
    'quantity': quantity,
    'unit': unit,
    'grams': grams,
    'nutritionSnapshot': {
      'energyKcal': energyKcal,
      'proteinG': proteinG,
      'fiberG': fiberG,
    },
    'inventoryStatus': inventoryStatus,
  };
}

class CatalogMealLine {
  const CatalogMealLine({
    required this.food,
    required this.serving,
    required this.quantity,
  });

  final CatalogFood food;
  final FoodServing serving;
  final double quantity;

  double get grams => serving.grams * quantity;
  NutritionSnapshot get nutrition => food.nutritionFor(grams);

  Map<String, dynamic> toMap({String? lineId}) => {
    'lineId': lineId ?? food.id,
    'foodId': food.id,
    'displayName': food.name,
    'quantity': quantity,
    'unit': serving.label,
    'grams': grams,
    'nutritionSnapshot': {
      'energyKcal': nutrition.energyKcal,
      'proteinG': nutrition.proteinG,
      'fiberG': nutrition.fiberG,
    },
    'inventoryStatus': 'not_matched',
  };
}

bool _sameLocalDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;
