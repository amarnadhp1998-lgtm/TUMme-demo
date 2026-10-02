import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_capabilities.dart';
import '../data/meal_repository.dart';
import '../../kitchen/data/inventory_repository.dart';
import '../../../core/analytics/feature_analytics.dart';

class MealDetailScreen extends ConsumerWidget {
  const MealDetailScreen({required this.meal, super.key});
  final MealLog? meal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = meal;
    final inventory =
        ref.watch(inventoryProvider).value ?? const <InventoryItem>[];
    if (value == null) {
      return const Scaffold(body: Center(child: Text('Meal not available.')));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(_title(value.mealType)),
        actions: [
          IconButton(
            tooltip: 'Duplicate meal',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () async {
              await ref.read(mealRepositoryProvider).duplicate(value);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Meal duplicated for today.')),
                );
                context.pop();
              }
            },
          ),
          if (!AppCapabilities.mealDeletion)
            const IconButton(
              tooltip: 'Meal deletion unavailable in free demo',
              icon: Icon(Icons.delete_outline),
              onPressed: null,
            )
          else
            IconButton(
              tooltip: 'Delete meal',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete meal?'),
                    content: const Text(
                      'This removes the meal, reverses its exact kitchen deductions, and rebuilds nutrition totals.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                try {
                  await ref.read(mealRepositoryProvider).delete(value.id);
                  if (context.mounted) context.pop();
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Could not delete the meal. No partial deletion was applied.',
                        ),
                      ),
                    );
                  }
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            value.description,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 24),
          _Metric(
            label: 'Energy',
            value: '${value.energyKcal.toStringAsFixed(0)} kcal',
          ),
          _Metric(
            label: 'Protein',
            value: '${value.proteinG.toStringAsFixed(1)} g',
          ),
          _Metric(
            label: 'Fiber',
            value: '${value.fiberG.toStringAsFixed(1)} g',
          ),
          if (value.items.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text('Foods', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  for (var index = 0; index < value.items.length; index++) ...[
                    _FoodLine(
                      mealId: value.id,
                      item: value.items[index],
                      inventory: inventory,
                    ),
                    if (index != value.items.length - 1)
                      const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Text(
            value.items.isEmpty
                ? 'These totals were entered manually and saved with the meal.'
                : 'These nutrient values are immutable snapshots calculated when the meal was logged.',
          ),
        ],
      ),
    );
  }
}

class _FoodLine extends ConsumerWidget {
  const _FoodLine({
    required this.mealId,
    required this.item,
    required this.inventory,
  });
  final String mealId;
  final MealLineSnapshot item;
  final List<InventoryItem> inventory;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final matches = inventory
        .where(
          (candidate) =>
              candidate.foodId != null &&
              candidate.foodId == item.foodId &&
              candidate.quantity > 0,
        )
        .toList();
    final match = matches.length == 1 ? matches.single : null;
    final amount = match == null ? null : _deductionAmount(item, match);
    final batches = match == null
        ? const AsyncData<List<InventoryBatch>>([])
        : ref.watch(inventoryBatchesProvider(match.id));
    final canDeduct =
        match != null &&
        amount != null &&
        batches.value != null &&
        batches.value!.isNotEmpty;

    return ListTile(
      title: Text(item.displayName),
      subtitle: Text(
        '${item.quantity.toStringAsFixed(1)} × ${item.unit} · '
        '${item.grams.toStringAsFixed(0)} g'
        '${matches.length > 1 ? ' · multiple kitchen matches' : ''}',
      ),
      trailing: canDeduct
          ? TextButton(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Use kitchen stock?'),
                    content: Text(
                      'Deduct ${amount.toStringAsFixed(1)} ${match.unit} from '
                      '${match.name}, using the earliest-expiring batch first.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Deduct'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                final result = await ref
                    .read(inventoryRepositoryProvider)
                    .consumeFefo(
                      match.id,
                      amount,
                      idempotencyKey: '$mealId:${item.lineId}:consume-v1',
                      mealId: mealId,
                      mealLineId: item.lineId,
                    );
                await ref
                    .read(featureAnalyticsProvider)
                    .record(FeatureEvent.inventoryMatchConfirmed);
                if (context.mounted) {
                  final unresolved = result.unresolved > 0
                      ? ' ${result.unresolved.toStringAsFixed(1)} ${match.unit} was unavailable.'
                      : '';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Kitchen stock updated.$unresolved'),
                    ),
                  );
                }
              },
              child: const Text('Use stock'),
            )
          : Text('${item.energyKcal.toStringAsFixed(0)} kcal'),
    );
  }
}

double? _deductionAmount(MealLineSnapshot line, InventoryItem item) {
  return switch (item.unit) {
    'item' => line.quantity,
    'g' => line.grams,
    'kg' => line.grams / 1000,
    'ml' when line.unit.toLowerCase().contains('ml') => line.grams,
    'l' when line.unit.toLowerCase().contains('ml') => line.grams / 1000,
    _ => null,
  };
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    trailing: Text(value, style: Theme.of(context).textTheme.titleMedium),
  );
}

String _title(String value) =>
    value.isEmpty ? 'Meal' : '${value[0].toUpperCase()}${value.substring(1)}';
