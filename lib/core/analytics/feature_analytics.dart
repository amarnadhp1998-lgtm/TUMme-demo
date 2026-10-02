import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final featureAnalyticsProvider = Provider<FeatureAnalytics>((ref) {
  return FeatureAnalytics(FirebaseAnalytics.instance);
});

enum FeatureEvent {
  onboardingStarted,
  onboardingCompleted,
  mealAddStarted,
  mealLogged,
  inventoryMatchConfirmed,
  shoppingCompleted,
  groceryIntakeCompleted,
  coachMessageSent,
}

class FeatureAnalytics {
  const FeatureAnalytics(this.analytics);
  final FirebaseAnalytics analytics;

  Future<void> record(FeatureEvent event) async {
    try {
      await analytics.logEvent(
        name: switch (event) {
          FeatureEvent.onboardingStarted => 'onboarding_started',
          FeatureEvent.onboardingCompleted => 'onboarding_completed',
          FeatureEvent.mealAddStarted => 'meal_add_started',
          FeatureEvent.mealLogged => 'meal_logged',
          FeatureEvent.inventoryMatchConfirmed => 'inventory_match_confirmed',
          FeatureEvent.shoppingCompleted => 'shopping_completed',
          FeatureEvent.groceryIntakeCompleted => 'grocery_intake_completed',
          FeatureEvent.coachMessageSent => 'coach_message_sent',
        },
      );
    } catch (_) {
      // Telemetry must never block a user action.
    }
  }
}
