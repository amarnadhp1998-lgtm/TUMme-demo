import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_capabilities.dart';
import '../../../core/widgets/demo_unavailable.dart';
import '../data/meal_repository.dart';
import '../../../core/analytics/feature_analytics.dart';
import '../data/meal_parser_repository.dart';
import '../domain/food_catalog.dart';

enum MealEntryMode { search, describe, manual }

class AddMealScreen extends ConsumerStatefulWidget {
  const AddMealScreen({super.key});
  @override
  ConsumerState<AddMealScreen> createState() => _AddMealScreenState();
}

class _AddMealScreenState extends ConsumerState<AddMealScreen> {
  final formKey = GlobalKey<FormState>();
  final description = TextEditingController();
  final calories = TextEditingController();
  final protein = TextEditingController();
  final fiber = TextEditingController();
  final search = TextEditingController();
  final lines = <CatalogMealLine>[];
  late String mealType;
  MealEntryMode mode = MealEntryMode.search;
  final consumedAt = DateTime.now();
  bool busy = false;
  MealParseResult? parseResult;

  @override
  void initState() {
    super.initState();
    unawaited(
      ref.read(featureAnalyticsProvider).record(FeatureEvent.mealAddStarted),
    );
    mealType = switch (DateTime.now().hour) {
      < 11 => 'breakfast',
      < 16 => 'lunch',
      < 21 => 'dinner',
      _ => 'snack',
    };
  }

  @override
  void dispose() {
    for (final controller in [description, calories, protein, fiber, search]) {
      controller.dispose();
    }
    super.dispose();
  }

  NutritionSnapshot get totals => lines.fold(
    NutritionSnapshot.zero,
    (total, line) => total + line.nutrition,
  );

  Future<void> save() async {
    if (mode != MealEntryMode.manual && lines.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Add at least one food.')));
      return;
    }
    if (mode == MealEntryMode.manual && !formKey.currentState!.validate()) {
      return;
    }
    setState(() => busy = true);
    try {
      final repository = ref.read(mealRepositoryProvider);
      if (mode != MealEntryMode.manual) {
        await repository.addFromCatalog(
          mealType: mealType,
          consumedAt: consumedAt,
          lines: lines,
        );
      } else {
        await repository.add(
          mealType: mealType,
          description: description.text,
          consumedAt: consumedAt,
          energyKcal: double.parse(calories.text),
          proteinG: double.parse(protein.text),
          fiberG: double.parse(fiber.text),
        );
      }
      await ref.read(featureAnalyticsProvider).record(FeatureEvent.mealLogged);
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save this meal.')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Log meal')),
    body: Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          DropdownButtonFormField<String>(
            initialValue: mealType,
            decoration: const InputDecoration(labelText: 'Meal type'),
            items: const ['breakfast', 'lunch', 'dinner', 'snack']
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(_title(value)),
                  ),
                )
                .toList(),
            onChanged: busy
                ? null
                : (value) => setState(() => mealType = value!),
          ),
          const SizedBox(height: 16),
          SegmentedButton<MealEntryMode>(
            segments: [
              if (AppCapabilities.mealParsing)
                const ButtonSegment(
                  value: MealEntryMode.describe,
                  icon: Icon(Icons.auto_awesome_outlined),
                  label: Text('Describe'),
                ),
              const ButtonSegment(
                value: MealEntryMode.search,
                icon: Icon(Icons.search),
                label: Text('Search foods'),
              ),
              const ButtonSegment(
                value: MealEntryMode.manual,
                icon: Icon(Icons.edit_outlined),
                label: Text('Manual totals'),
              ),
            ],
            selected: {mode},
            onSelectionChanged: busy
                ? null
                : (selection) => setState(() => mode = selection.first),
          ),
          if (!AppCapabilities.mealParsing) ...[
            const SizedBox(height: 12),
            const DemoUnavailableCard(
              title: 'Meal description parsing unavailable in free demo',
              message: 'Use Search foods or Manual totals to log this meal.',
              icon: Icons.info_outline,
            ),
          ],
          const SizedBox(height: 20),
          if (mode == MealEntryMode.search)
            _searchMode()
          else if (mode == MealEntryMode.describe)
            _describeMode()
          else
            _manualMode(),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'Saving…' : 'Save meal'),
          ),
        ],
      ),
    ),
  );

  Widget _searchMode() {
    final query = search.text.trim().toLowerCase();
    final results = developmentFoodCatalog
        .where(
          (food) => query.isEmpty || food.name.toLowerCase().contains(query),
        )
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: search,
          decoration: const InputDecoration(
            labelText: 'Search foods',
            prefixIcon: Icon(Icons.search),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        const Text(
          'Development food fixtures. Replace with the approved production data provider before release.',
        ),
        const SizedBox(height: 12),
        for (final food in results)
          Card(
            child: ListTile(
              title: Text(food.name),
              subtitle: Text(
                '${food.energyKcalPer100g.toStringAsFixed(0)} kcal · '
                '${food.proteinGPer100g.toStringAsFixed(1)} g protein per 100 g',
              ),
              trailing: const Icon(Icons.add_circle_outline),
              onTap: () => _chooseServing(food),
            ),
          ),
        if (results.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('No matching fixture food.'),
          ),
        if (lines.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Meal items', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                for (var index = 0; index < lines.length; index++) ...[
                  ListTile(
                    title: Text(lines[index].food.name),
                    subtitle: Text(
                      '${lines[index].quantity.toStringAsFixed(1)} × '
                      '${lines[index].serving.label} · '
                      '${lines[index].nutrition.energyKcal.toStringAsFixed(0)} kcal',
                    ),
                    trailing: IconButton(
                      tooltip: 'Remove ${lines[index].food.name}',
                      onPressed: () => setState(() => lines.removeAt(index)),
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ),
                  if (index != lines.length - 1) const Divider(height: 1),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _TotalsCard(totals: totals),
        ],
      ],
    );
  }

  Widget _manualMode() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextFormField(
        controller: description,
        minLines: 3,
        maxLines: 6,
        decoration: const InputDecoration(
          labelText: 'What did you eat?',
          hintText: 'For example: rice, dal, spinach and curd',
        ),
        validator: (value) => value == null || value.trim().isEmpty
            ? 'Describe your meal.'
            : null,
      ),
      const SizedBox(height: 16),
      const Text('Enter values from a food label or approved source.'),
      const SizedBox(height: 12),
      _NumberField(controller: calories, label: 'Energy (kcal)'),
      const SizedBox(height: 12),
      _NumberField(controller: protein, label: 'Protein (g)'),
      const SizedBox(height: 12),
      _NumberField(controller: fiber, label: 'Fiber (g)'),
    ],
  );

  Widget _describeMode() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: description,
        minLines: 3,
        maxLines: 6,
        decoration: const InputDecoration(
          labelText: 'Describe your meal',
          hintText: 'For example: 2 boiled eggs, a banana and 250 ml milk',
        ),
      ),
      const SizedBox(height: 12),
      FilledButton.tonalIcon(
        onPressed: busy ? null : _parseDescription,
        icon: const Icon(Icons.auto_awesome_outlined),
        label: Text(busy ? 'Parsing…' : 'Parse for review'),
      ),
      if (parseResult != null) ...[
        const SizedBox(height: 20),
        Text(
          'Review parsed items',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        for (final item in parseResult!.items)
          ListTile(
            leading: Icon(
              item.needsConfirmation
                  ? Icons.warning_amber
                  : Icons.check_circle_outline,
            ),
            title: Text(item.displayName),
            subtitle: Text(
              item.quantity == null
                  ? 'Quantity needs confirmation'
                  : '${item.quantity} ${item.unit ?? ''} · ${(item.confidence * 100).toStringAsFixed(0)}% match',
            ),
            trailing: const Icon(Icons.edit_outlined),
            onTap: item.foodId == null
                ? null
                : () {
                    final matches = developmentFoodCatalog.where(
                      (food) => food.id == item.foodId,
                    );
                    if (matches.isNotEmpty) _chooseServing(matches.single);
                  },
          ),
        if (parseResult!.unresolvedText.isNotEmpty)
          Text('Unresolved: ${parseResult!.unresolvedText.join(', ')}'),
        const SizedBox(height: 8),
        Text(
          '${lines.length} confirmed catalog item${lines.length == 1 ? '' : 's'} ready to save.',
        ),
      ],
    ],
  );

  Future<void> _parseDescription() async {
    if (!AppCapabilities.mealParsing) return;
    final text = description.text.trim();
    if (text.isEmpty) return;
    setState(() => busy = true);
    try {
      final result = await ref
          .read(mealParserRepositoryProvider)
          .parse(text: text, mealType: mealType);
      final resolved = <CatalogMealLine>[];
      for (final item in result.items) {
        if (item.foodId == null ||
            item.quantity == null ||
            item.needsConfirmation) {
          continue;
        }
        final matches = developmentFoodCatalog.where(
          (food) => food.id == item.foodId,
        );
        if (matches.isEmpty) continue;
        final food = matches.single;
        final servings = food.servings.where(
          (serving) => serving.label == item.unit,
        );
        resolved.add(
          CatalogMealLine(
            food: food,
            serving: servings.isEmpty ? food.servings.first : servings.first,
            quantity: item.quantity!,
          ),
        );
      }
      if (mounted) {
        setState(() {
          parseResult = result;
          lines
            ..clear()
            ..addAll(resolved);
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not parse this meal. Use Search foods to review it manually.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _chooseServing(CatalogFood food) async {
    var serving = food.servings.first;
    final quantity = TextEditingController(text: '1');
    final result = await showModalBottomSheet<CatalogMealLine>(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(food.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              DropdownButtonFormField<FoodServing>(
                initialValue: serving,
                decoration: const InputDecoration(labelText: 'Serving'),
                items: food.servings
                    .map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.label),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setSheetState(() => serving = value!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: quantity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Number of servings',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  final parsed = double.tryParse(quantity.text);
                  if (parsed == null || parsed <= 0) return;
                  Navigator.pop(
                    context,
                    CatalogMealLine(
                      food: food,
                      serving: serving,
                      quantity: parsed,
                    ),
                  );
                },
                child: const Text('Add to meal'),
              ),
            ],
          ),
        ),
      ),
    );
    quantity.dispose();
    if (result != null && mounted) setState(() => lines.add(result));
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals});
  final NutritionSnapshot totals;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        '${totals.energyKcal.toStringAsFixed(0)} kcal · '
        '${totals.proteinG.toStringAsFixed(1)} g protein · '
        '${totals.fiberG.toStringAsFixed(1)} g fiber',
        style: Theme.of(context).textTheme.titleMedium,
      ),
    ),
  );
}

class _NumberField extends StatelessWidget {
  const _NumberField({required this.controller, required this.label});
  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(labelText: label),
    validator: (value) {
      final parsed = double.tryParse(value ?? '');
      return parsed == null || parsed < 0 ? 'Enter a valid value.' : null;
    },
  );
}

String _title(String value) => '${value[0].toUpperCase()}${value.substring(1)}';
