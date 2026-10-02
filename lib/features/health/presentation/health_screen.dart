import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_capabilities.dart';
import '../../meals/data/meal_repository.dart' hide dailyNutritionProvider;
import '../data/health_aggregate_repository.dart';
import '../data/hydration_repository.dart';

class HealthScreen extends ConsumerStatefulWidget {
  const HealthScreen({super.key});

  @override
  ConsumerState<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends ConsumerState<HealthScreen> {
  int days = 1;

  @override
  Widget build(BuildContext context) {
    final meals = ref.watch(mealsProvider);
    final hydration = ref.watch(hydrationLogsProvider);
    final aggregates = AppCapabilities.serverAggregates
        ? ref.watch(dailyNutritionProvider).value
        : null;
    return Scaffold(
      appBar: AppBar(title: const Text('Health')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(mealsProvider);
          ref.invalidate(hydrationLogsProvider);
          if (AppCapabilities.serverAggregates) {
            ref.invalidate(dailyNutritionProvider);
          }
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 1, label: Text('Today')),
                ButtonSegment(value: 7, label: Text('7 days')),
                ButtonSegment(value: 30, label: Text('30 days')),
              ],
              selected: {days},
              onSelectionChanged: (value) =>
                  setState(() => days = value.single),
            ),
            const SizedBox(height: 20),
            if (aggregates != null && aggregates.isNotEmpty)
              _AggregateHealthSummary(days: days, values: aggregates)
            else
              switch ((meals, hydration)) {
                (
                  AsyncData(value: final mealValues),
                  AsyncData(value: final waterValues),
                ) =>
                  _HealthSummary(
                    days: days,
                    meals: mealValues,
                    hydration: waterValues,
                  ),
                (AsyncError(), _) || (_, AsyncError()) => const Center(
                  child: Text('Could not load health trends.'),
                ),
                _ => const Center(child: CircularProgressIndicator()),
              },
          ],
        ),
      ),
    );
  }
}

class _AggregateHealthSummary extends StatelessWidget {
  const _AggregateHealthSummary({required this.days, required this.values});

  final int days;
  final List<DailyNutritionAggregate> values;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days - 1));
    final selected = values.where((value) => !value.date.isBefore(start));
    final plants = <String>{
      for (final value in selected) ...value.plantFoodIds,
    };
    double total(double Function(DailyNutritionAggregate value) read) =>
        selected.fold(0, (sum, value) => sum + read(value));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _TrendCard(
              label: 'Energy',
              value: total((value) => value.energyKcal).toStringAsFixed(0),
              unit: 'kcal',
            ),
            _TrendCard(
              label: 'Protein',
              value: total((value) => value.proteinG).toStringAsFixed(1),
              unit: 'g',
            ),
            _TrendCard(
              label: 'Fiber',
              value: total((value) => value.fiberG).toStringAsFixed(1),
              unit: 'g',
            ),
            _TrendCard(
              label: 'Water',
              value: total((value) => value.waterMl).toStringAsFixed(0),
              unit: 'ml',
            ),
          ],
        ),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: const Icon(Icons.eco_outlined),
            title: Text(
              '${plants.length} unique plant food${plants.length == 1 ? '' : 's'}',
            ),
            subtitle: const Text(
              'Calculated from deterministic daily nutrition snapshots.',
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () async {
            await showModalBottomSheet<void>(
              context: context,
              builder: (context) => _WaterSheet(),
            );
          },
          icon: const Icon(Icons.water_drop_outlined),
          label: const Text('Log water'),
        ),
      ],
    );
  }
}

class _HealthSummary extends StatelessWidget {
  const _HealthSummary({
    required this.days,
    required this.meals,
    required this.hydration,
  });

  final int days;
  final List<MealLog> meals;
  final List<HydrationLog> hydration;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final start = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: days - 1));
    final selectedMeals = meals
        .where((meal) => !meal.consumedAt.isBefore(start))
        .toList();
    final selectedWater = hydration
        .where((log) => !log.loggedAt.isBefore(start))
        .toList();
    final energy = selectedMeals.fold(
      0.0,
      (sum, meal) => sum + meal.energyKcal,
    );
    final protein = selectedMeals.fold(0.0, (sum, meal) => sum + meal.proteinG);
    final fiber = selectedMeals.fold(0.0, (sum, meal) => sum + meal.fiberG);
    final water = selectedWater.fold(0.0, (sum, log) => sum + log.amountMl);
    final plants = <String>{
      for (final meal in selectedMeals)
        for (final item in meal.items)
          if (item.foodId != null && _plantFoodIds.contains(item.foodId))
            item.foodId!,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _TrendCard(
              label: 'Energy',
              value: energy.toStringAsFixed(0),
              unit: 'kcal',
            ),
            _TrendCard(
              label: 'Protein',
              value: protein.toStringAsFixed(1),
              unit: 'g',
            ),
            _TrendCard(
              label: 'Fiber',
              value: fiber.toStringAsFixed(1),
              unit: 'g',
            ),
            _TrendCard(
              label: 'Water',
              value: water.toStringAsFixed(0),
              unit: 'ml',
            ),
          ],
        ),
        const SizedBox(height: 20),
        Card(
          child: ListTile(
            leading: const Icon(Icons.eco_outlined),
            title: Text(
              '${plants.length} unique plant food${plants.length == 1 ? '' : 's'}',
            ),
            subtitle: Text(
              days == 1
                  ? 'Logged today. Repeats count once.'
                  : 'Logged in the selected period. Repeats count once.',
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () async {
            await showModalBottomSheet<void>(
              context: context,
              builder: (context) => _WaterSheet(),
            );
          },
          icon: const Icon(Icons.water_drop_outlined),
          label: const Text('Log water'),
        ),
      ],
    );
  }
}

class _WaterSheet extends ConsumerWidget {
  _WaterSheet();
  final controller = TextEditingController(text: '250');

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      24,
      24,
      MediaQuery.viewInsetsOf(context).bottom + 24,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Log water', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 16),
        TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount (ml)'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: () async {
            final amount = double.tryParse(controller.text);
            if (amount == null || amount <= 0 || amount > 5000) return;
            await ref.read(hydrationRepositoryProvider).add(amount);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Add water'),
        ),
      ],
    ),
  );
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.label,
    required this.value,
    required this.unit,
  });
  final String label;
  final String value;
  final String unit;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label, $value $unit',
    readOnly: true,
    child: ExcludeSemantics(
      child: SizedBox(
        width: MediaQuery.textScalerOf(
          context,
        ).scale(156).clamp(156, 260).toDouble(),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                const SizedBox(height: 6),
                Text(
                  '$value $unit',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

const _plantFoodIds = {
  'banana_raw',
  'oats_dry',
  'rice_white_cooked',
  'lentils_cooked',
  'spinach_cooked',
  'whole_wheat_bread',
};
