abstract final class AppCapabilities {
  const AppCapabilities._();

  static const bool sparkDemo = bool.fromEnvironment(
    'SPARK_DEMO',
    defaultValue: false,
  );

  static const bool cloudAi = !sparkDemo;
  static const bool mealParsing = !sparkDemo;
  static const bool mealDeletion = !sparkDemo;
  static const bool groceryIntake = !sparkDemo;
  static const bool dataExportAndAccountDeletion = !sparkDemo;
  static const bool notifications = !sparkDemo;
  static const bool serverAggregates = !sparkDemo;
}
