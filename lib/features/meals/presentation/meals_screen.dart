import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/meal_repository.dart';

class MealsScreen extends ConsumerStatefulWidget {
  const MealsScreen({super.key});

  @override
  ConsumerState<MealsScreen> createState() => _MealsScreenState();
}

class _MealsScreenState extends ConsumerState<MealsScreen> {
  DateTime selectedDate = _dateOnly(DateTime.now());

  @override
  Widget build(BuildContext context) {
    final daily = ref.watch(dailyNutritionProvider(selectedDate));
    return Scaffold(
      appBar: AppBar(title: const Text('Meals')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/meals/add'),
        icon: const Icon(Icons.add),
        label: const Text('Log meal'),
      ),
      body: Column(
        children: [
          _DateSelector(
            date: selectedDate,
            onPrevious: () => setState(
              () =>
                  selectedDate = selectedDate.subtract(const Duration(days: 1)),
            ),
            onNext: _isToday(selectedDate)
                ? null
                : () => setState(
                    () => selectedDate = selectedDate.add(
                      const Duration(days: 1),
                    ),
                  ),
            onToday: () =>
                setState(() => selectedDate = _dateOnly(DateTime.now())),
          ),
          Expanded(
            child: daily.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: FilledButton.tonal(
                  onPressed: () => ref.invalidate(mealsProvider),
                  child: const Text('Retry loading meals'),
                ),
              ),
              data: (summary) => summary.meals.isEmpty
                  ? const _EmptyMeals()
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                      children: [
                        _DailyTotals(summary: summary),
                        const SizedBox(height: 16),
                        for (final type in const [
                          'breakfast',
                          'lunch',
                          'dinner',
                          'snack',
                        ])
                          if (summary.meals.any(
                            (meal) => meal.mealType == type,
                          ))
                            _MealSection(
                              title: _title(type),
                              meals: summary.meals
                                  .where((meal) => meal.mealType == type)
                                  .toList(),
                            ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DateSelector extends StatelessWidget {
  const _DateSelector({
    required this.date,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
  });
  final DateTime date;
  final VoidCallback onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    child: Row(
      children: [
        IconButton(
          tooltip: 'Previous day',
          onPressed: onPrevious,
          icon: const Icon(Icons.chevron_left),
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                _isToday(date) ? 'Today' : _weekday(date),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(_dateLabel(date)),
            ],
          ),
        ),
        IconButton(
          tooltip: 'Next day',
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
        ),
        if (!_isToday(date))
          TextButton(onPressed: onToday, child: const Text('Today')),
      ],
    ),
  );
}

class _DailyTotals extends StatelessWidget {
  const _DailyTotals({required this.summary});
  final DailyNutrition summary;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Daily total', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            '${summary.energyKcal.toStringAsFixed(0)} kcal · '
            '${summary.proteinG.toStringAsFixed(1)} g protein · '
            '${summary.fiberG.toStringAsFixed(1)} g fiber',
          ),
          const SizedBox(height: 4),
          Text(
            '${summary.meals.length} meal${summary.meals.length == 1 ? '' : 's'}',
          ),
        ],
      ),
    ),
  );
}

class _MealSection extends StatelessWidget {
  const _MealSection({required this.title, required this.meals});
  final String title;
  final List<MealLog> meals;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        Card(
          child: Column(
            children: [
              for (var index = 0; index < meals.length; index++) ...[
                ListTile(
                  leading: CircleAvatar(
                    child: Text(_mealIcon(meals[index].mealType)),
                  ),
                  title: Text(meals[index].description),
                  subtitle: Text(
                    '${_time(meals[index].consumedAt)} · '
                    '${meals[index].proteinG.toStringAsFixed(1)} g protein · '
                    '${meals[index].fiberG.toStringAsFixed(1)} g fiber',
                  ),
                  trailing: Text(
                    '${meals[index].energyKcal.toStringAsFixed(0)} kcal',
                  ),
                  onTap: () => context.push(
                    '/meals/${meals[index].id}',
                    extra: meals[index],
                  ),
                ),
                if (index != meals.length - 1) const Divider(height: 1),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _EmptyMeals extends StatelessWidget {
  const _EmptyMeals();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.restaurant_outlined, size: 56),
          SizedBox(height: 16),
          Text('No meals logged for this day'),
          SizedBox(height: 8),
          Text('Choose another date or log a meal.'),
        ],
      ),
    ),
  );
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);
bool _isToday(DateTime value) => _dateOnly(value) == _dateOnly(DateTime.now());
String _title(String value) => '${value[0].toUpperCase()}${value.substring(1)}';
String _mealIcon(String value) => switch (value) {
  'breakfast' => '☀',
  'lunch' => '◐',
  'dinner' => '☾',
  _ => '•',
};
String _time(DateTime value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _dateLabel(DateTime value) =>
    '${value.day}/${value.month}/${value.year}';
String _weekday(DateTime value) => const [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
][value.weekday - 1];
