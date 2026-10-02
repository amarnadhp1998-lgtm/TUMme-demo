import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_capabilities.dart';

final coachRepositoryProvider = Provider<CoachRepository>((ref) {
  return CoachRepository(FirebaseFunctions.instanceFor(region: 'asia-south1'));
});

class CoachRepository {
  const CoachRepository(this.functions);
  final FirebaseFunctions functions;

  Future<CoachReply> ask(String message) async {
    if (!AppCapabilities.cloudAi) {
      throw UnsupportedError('Cloud AI is unavailable in the free demo.');
    }
    final result = await functions
        .httpsCallable('askCoach')
        .call<Map<String, dynamic>>({'message': message});
    final response = result.data['message'];
    if (response is! String || response.trim().isEmpty) {
      throw StateError('Coach returned an invalid response.');
    }
    final actions = (result.data['actions'] as List<dynamic>? ?? const [])
        .whereType<Map<dynamic, dynamic>>()
        .map(CoachAction.fromMap)
        .where(
          (action) =>
              action.requiresConfirmation &&
              (action.type == 'LOG_WATER' || action.type == 'ADD_GROCERY_ITEM'),
        )
        .toList();
    return CoachReply(message: response, actions: actions);
  }
}

class CoachReply {
  const CoachReply({required this.message, required this.actions});
  final String message;
  final List<CoachAction> actions;
}

class CoachAction {
  const CoachAction({
    required this.type,
    required this.requiresConfirmation,
    required this.name,
    required this.quantity,
    required this.unit,
  });
  final String type;
  final bool requiresConfirmation;
  final String? name;
  final double? quantity;
  final String? unit;

  factory CoachAction.fromMap(Map<dynamic, dynamic> data) {
    final payload = data['payload'] as Map<dynamic, dynamic>? ?? const {};
    return CoachAction(
      type: data['type'] as String? ?? 'NONE',
      requiresConfirmation: data['requiresConfirmation'] == true,
      name: payload['name'] as String?,
      quantity: (payload['quantity'] as num?)?.toDouble(),
      unit: payload['unit'] as String?,
    );
  }
}
