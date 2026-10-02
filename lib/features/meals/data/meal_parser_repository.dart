import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_capabilities.dart';

final mealParserRepositoryProvider = Provider<MealParserRepository>((ref) {
  return MealParserRepository(
    FirebaseFunctions.instanceFor(region: 'asia-south1'),
  );
});

class ParsedMealItem {
  const ParsedMealItem({
    required this.foodId,
    required this.displayName,
    required this.quantity,
    required this.unit,
    required this.confidence,
    required this.needsConfirmation,
  });
  final String? foodId;
  final String displayName;
  final double? quantity;
  final String? unit;
  final double confidence;
  final bool needsConfirmation;
}

class MealParseResult {
  const MealParseResult({required this.items, required this.unresolvedText});
  final List<ParsedMealItem> items;
  final List<String> unresolvedText;
}

class MealParserRepository {
  const MealParserRepository(this.functions);
  final FirebaseFunctions functions;

  Future<MealParseResult> parse({
    required String text,
    required String mealType,
  }) async {
    if (!AppCapabilities.mealParsing) {
      throw UnsupportedError('Meal parsing is unavailable in the free demo.');
    }
    final result = await functions
        .httpsCallable('parseMeal')
        .call<Map<String, dynamic>>({'text': text, 'mealType': mealType});
    final data = result.data;
    final items = (data['items'] as List<dynamic>? ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map(
          (item) => ParsedMealItem(
            foodId: item['foodId'] as String?,
            displayName: item['displayName'] as String? ?? 'Food',
            quantity: (item['quantity'] as num?)?.toDouble(),
            unit: item['unit'] as String?,
            confidence: (item['confidence'] as num?)?.toDouble() ?? 0,
            needsConfirmation: item['needsConfirmation'] == true,
          ),
        )
        .toList();
    return MealParseResult(
      items: items,
      unresolvedText: (data['unresolvedText'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
    );
  }
}
