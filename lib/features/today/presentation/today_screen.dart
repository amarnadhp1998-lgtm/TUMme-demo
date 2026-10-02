import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_capabilities.dart';
import '../../grocery/data/grocery_repository.dart';
import '../../kitchen/data/inventory_repository.dart';
import '../../meals/data/meal_repository.dart';
import '../../health/data/hydration_repository.dart';
import '../../coach/presentation/coach_screen.dart';
import '../../notifications/data/notification_repository.dart';

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final meals = ref.watch(
      dailyNutritionProvider(DateTime(now.year, now.month, now.day)),
    );
    final inventory = ref.watch(inventoryProvider);
    final groceries = ref.watch(groceryItemsProvider);
    final hydration = ref.watch(hydrationLogsProvider);
    final firstName = FirebaseAuth.instance.currentUser?.displayName
        ?.trim()
        .split(RegExp(r'\s+'))
        .first;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Today'),
        actions: [
          if (AppCapabilities.notifications)
            IconButton(
              tooltip: 'Notifications',
              onPressed: () => context.push('/notifications'),
              icon: Badge(
                isLabelVisible: ref.watch(unreadNotificationCountProvider) > 0,
                label: Text(
                  ref
                      .watch(unreadNotificationCountProvider)
                      .clamp(0, 99)
                      .toString(),
                ),
                child: const Icon(Icons.notifications_outlined),
              ),
            )
          else
            IconButton(
              tooltip: 'Notifications unavailable in free demo',
              onPressed: () => context.push('/notifications'),
              icon: const Icon(Icons.notifications_off_outlined),
            ),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(mealsProvider);
          ref.invalidate(inventoryProvider);
          ref.invalidate(groceryItemsProvider);
          ref.invalidate(hydrationLogsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            Text(
              firstName == null || firstName.isEmpty
                  ? 'Your day at a glance'
                  : 'Hello, $firstName',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(_dateLabel(DateTime.now())),
            const SizedBox(height: 20),
            meals.when(
              loading: () => const _LoadingCard(),
              error: (_, _) => _ErrorCard(
                message: 'Could not load today’s nutrition.',
                onRetry: () => ref.invalidate(mealsProvider),
              ),
              data: (summary) {
                final todayMeals = summary.meals;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _MetricCard(
                          label: 'Energy',
                          value: summary.energyKcal.toStringAsFixed(0),
                          unit: 'kcal',
                          icon: Icons.local_fire_department_outlined,
                        ),
                        _MetricCard(
                          label: 'Protein',
                          value: summary.proteinG.toStringAsFixed(1),
                          unit: 'g',
                          icon: Icons.fitness_center_outlined,
                        ),
                        _MetricCard(
                          label: 'Fiber',
                          value: summary.fiberG.toStringAsFixed(1),
                          unit: 'g',
                          icon: Icons.eco_outlined,
                        ),
                        hydration.maybeWhen(
                          data: (logs) {
                            final todayMl = logs
                                .where((log) => _sameDay(log.loggedAt, now))
                                .fold(0.0, (sum, log) => sum + log.amountMl);
                            return _MetricCard(
                              label: 'Water',
                              value: todayMl.toStringAsFixed(0),
                              unit: 'ml',
                              icon: Icons.water_drop_outlined,
                            );
                          },
                          orElse: () => const SizedBox.shrink(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton.icon(
                      onPressed: () =>
                          ref.read(hydrationRepositoryProvider).add(250),
                      icon: const Icon(Icons.water_drop_outlined),
                      label: const Text('Log 250 ml water'),
                    ),
                    const SizedBox(height: 20),
                    _SectionHeader(
                      title: 'Meals',
                      actionLabel: 'Add meal',
                      onPressed: () => context.push('/meals/add'),
                    ),
                    if (todayMeals.isEmpty)
                      const _EmptyCard(
                        icon: Icons.restaurant_outlined,
                        text: 'No meals logged today.',
                      )
                    else
                      Card(
                        child: Column(
                          children: [
                            for (
                              var index = 0;
                              index < todayMeals.length;
                              index++
                            ) ...[
                              _MealRow(meal: todayMeals[index]),
                              if (index != todayMeals.length - 1)
                                const Divider(height: 1),
                            ],
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            Text(
              'Kitchen and grocery',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            inventory.when(
              loading: () => const _LoadingCard(),
              error: (_, _) => _ErrorCard(
                message: 'Could not load kitchen status.',
                onRetry: () => ref.invalidate(inventoryProvider),
              ),
              data: (items) {
                final cutoff = DateTime.now().add(const Duration(days: 3));
                final expiring = items.where((item) {
                  final expiry = item.expiryDate;
                  return expiry != null && expiry.isBefore(cutoff);
                }).toList();
                return _ActionCard(
                  icon: Icons.event_busy_outlined,
                  title: expiring.isEmpty
                      ? 'Nothing expiring soon'
                      : '${expiring.length} item${expiring.length == 1 ? '' : 's'} expiring soon',
                  subtitle: expiring.isEmpty
                      ? 'Your next three days look clear.'
                      : expiring.take(3).map((item) => item.name).join(', '),
                  onTap: () => context.go('/home/kitchen'),
                );
              },
            ),
            groceries.when(
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
              data: (items) {
                final remaining = items
                    .where(
                      (item) =>
                          item.status == 'accepted' ||
                          item.status == 'suggested',
                    )
                    .length;
                return _ActionCard(
                  icon: Icons.shopping_basket_outlined,
                  title:
                      '$remaining grocery item${remaining == 1 ? '' : 's'} remaining',
                  subtitle: remaining == 0
                      ? 'Your grocery list is clear.'
                      : 'Open the list to review what you need.',
                  onTap: () => context.go('/home/grocery'),
                );
              },
            ),
            const SizedBox(height: 20),
            if (meals.value != null &&
                inventory.value != null &&
                hydration.value != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('TUM Insight'),
                  subtitle: Text(
                    buildContextualCoachReply(
                      question: 'What should I focus on today?',
                      meals: meals.value!.meals,
                      inventory: inventory.value!,
                      hydration: hydration.value!,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/coach'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

bool _sameDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.unit,
    required this.icon,
  });
  final String label;
  final String value;
  final String unit;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label, $value $unit',
    readOnly: true,
    child: ExcludeSemantics(
      child: SizedBox(
        width: MediaQuery.textScalerOf(
          context,
        ).scale(110).clamp(110, 200).toDouble(),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon),
                const SizedBox(height: 12),
                Text(label, style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 2),
                Text(
                  '$value $unit',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _MealRow extends StatelessWidget {
  const _MealRow({required this.meal});
  final MealLog meal;

  @override
  Widget build(BuildContext context) => ListTile(
    title: Text(_title(meal.mealType)),
    subtitle: Text(
      meal.description,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    ),
    trailing: Text('${meal.energyKcal.toStringAsFixed(0)} kcal'),
    onTap: () => context.push('/meals/${meal.id}', extra: meal),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.actionLabel,
    required this.onPressed,
  });
  final String title;
  final String actionLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(title, style: Theme.of(context).textTheme.titleLarge),
      ),
      TextButton(onPressed: onPressed, child: Text(actionLabel)),
    ],
  );
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();
  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Loading content',
    child: const Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      ),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      title: Text(message),
      trailing: TextButton(onPressed: onRetry, child: const Text('Retry')),
    ),
  );
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Row(children: [Icon(icon), const SizedBox(width: 12), Text(text)]),
    ),
  );
}

String _title(String value) =>
    value.isEmpty ? 'Meal' : '${value[0].toUpperCase()}${value.substring(1)}';

String _dateLabel(DateTime value) {
  const weekdays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${weekdays[value.weekday - 1]}, ${months[value.month - 1]} ${value.day}';
}
