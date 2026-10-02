import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_capabilities.dart';
import '../../health/data/hydration_repository.dart';
import '../../../core/analytics/feature_analytics.dart';
import '../../../core/widgets/demo_unavailable.dart';
import '../../grocery/data/grocery_repository.dart';
import '../../kitchen/data/inventory_repository.dart';
import '../../meals/data/meal_repository.dart';
import '../data/coach_repository.dart';

class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key});

  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  final input = TextEditingController();
  final messages = <({bool user, String text})>[];
  bool busy = false;
  List<CoachAction> proposedActions = const [];

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> ask(String question) async {
    await ref
        .read(featureAnalyticsProvider)
        .record(FeatureEvent.coachMessageSent);
    final meals = ref.read(mealsProvider).value ?? const <MealLog>[];
    final inventory =
        ref.read(inventoryProvider).value ?? const <InventoryItem>[];
    final hydration =
        ref.read(hydrationLogsProvider).value ?? const <HydrationLog>[];
    setState(() {
      messages.add((user: true, text: question));
      input.clear();
      busy = true;
    });
    String reply;
    var actions = const <CoachAction>[];
    if (!AppCapabilities.cloudAi) {
      reply = buildContextualCoachReply(
        question: question,
        meals: meals,
        inventory: inventory,
        hydration: hydration,
      );
    } else {
      try {
        final result = await ref.read(coachRepositoryProvider).ask(question);
        reply = result.message;
        actions = result.actions;
      } catch (_) {
        reply = buildContextualCoachReply(
          question: question,
          meals: meals,
          inventory: inventory,
          hydration: hydration,
        );
      }
    }
    if (!mounted) return;
    setState(() {
      messages.add((user: false, text: reply));
      proposedActions = actions;
      busy = false;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Ask TUM')),
    body: Column(
      children: [
        if (!AppCapabilities.cloudAi)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: DemoUnavailableCard(
              title: 'Cloud coach unavailable in free demo',
              message:
                  'TUM will give a simple on-device summary of your saved meals, water, and kitchen.',
              icon: Icons.info_outline,
            ),
          ),
        Expanded(
          child: messages.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    const Icon(Icons.auto_awesome_outlined, size: 48),
                    const SizedBox(height: 16),
                    Text(
                      'What would help?',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Answers use only your logged meals, water, and current kitchen.',
                    ),
                    const SizedBox(height: 24),
                    for (final prompt in const [
                      'What should I eat next?',
                      'How is my hydration today?',
                      'What should I use soon?',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OutlinedButton(
                          onPressed: () => ask(prompt),
                          child: Text(prompt),
                        ),
                      ),
                  ],
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    return Semantics(
                      label: '${message.user ? 'You' : 'TUM'}: ${message.text}',
                      liveRegion: !message.user,
                      excludeSemantics: true,
                      child: Align(
                        alignment: message.user
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Card(
                          color: message.user
                              ? Theme.of(context).colorScheme.primaryContainer
                              : null,
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(message.text),
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (proposedActions.isNotEmpty)
          SizedBox(
            height: 92,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              scrollDirection: Axis.horizontal,
              itemCount: proposedActions.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final action = proposedActions[index];
                return ActionChip(
                  avatar: Icon(
                    action.type == 'LOG_WATER'
                        ? Icons.water_drop_outlined
                        : Icons.add_shopping_cart_outlined,
                  ),
                  label: Text(_actionLabel(action)),
                  onPressed: () => _confirmAction(action),
                );
              },
            ),
          ),
        SafeArea(
          minimum: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: input,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (value) {
                    final text = value.trim();
                    if (text.isNotEmpty) ask(text);
                  },
                  decoration: const InputDecoration(
                    hintText: 'Ask about today or your kitchen',
                  ),
                ),
              ),
              IconButton.filled(
                tooltip: 'Send',
                onPressed: busy
                    ? null
                    : () {
                        final text = input.text.trim();
                        if (text.isNotEmpty) ask(text);
                      },
                icon: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  String _actionLabel(CoachAction action) {
    if (action.type == 'LOG_WATER') {
      return 'Log ${action.quantity?.toStringAsFixed(0) ?? ''} ml';
    }
    return 'Add ${action.name ?? 'item'} to grocery';
  }

  Future<void> _confirmAction(CoachAction action) async {
    if (!action.requiresConfirmation) return;
    final isValidWater =
        action.type == 'LOG_WATER' &&
        action.quantity != null &&
        action.quantity! > 0;
    final isValidGrocery =
        action.type == 'ADD_GROCERY_ITEM' &&
        action.name?.trim().isNotEmpty == true &&
        action.quantity != null &&
        action.quantity! > 0 &&
        action.unit != null;
    if (!isValidWater && !isValidGrocery) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This suggested action is incomplete.')),
      );
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm action'),
        content: Text(_actionLabel(action)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    try {
      if (isValidWater) {
        await ref.read(hydrationRepositoryProvider).add(action.quantity!);
      } else if (isValidGrocery) {
        await ref
            .read(groceryRepositoryProvider)
            .add(
              name: action.name!,
              quantity: action.quantity!,
              unit: action.unit!,
            );
      }
      if (mounted) {
        setState(
          () => proposedActions = proposedActions
              .where((value) => value != action)
              .toList(),
        );
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Action completed.')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not complete this action.')),
        );
      }
    }
  }
}

String buildContextualCoachReply({
  required String question,
  required List<MealLog> meals,
  required List<InventoryItem> inventory,
  required List<HydrationLog> hydration,
}) {
  final now = DateTime.now();
  final todayMeals = meals
      .where((meal) => _sameDay(meal.consumedAt, now))
      .toList();
  final todayWater = hydration
      .where((log) => _sameDay(log.loggedAt, now))
      .fold(0.0, (sum, log) => sum + log.amountMl);
  final protein = todayMeals.fold(0.0, (sum, meal) => sum + meal.proteinG);
  final soon = inventory.where((item) {
    final expiry = item.expiryDate;
    return item.quantity > 0 &&
        expiry != null &&
        expiry.isBefore(now.add(const Duration(days: 3)));
  }).toList();
  final lower = question.toLowerCase();
  if (lower.contains('hydrat') || lower.contains('water')) {
    return todayWater == 0
        ? 'You have no water logged today. Log what you have already had so I can reflect it accurately.'
        : 'You have logged ${todayWater.toStringAsFixed(0)} ml of water today.';
  }
  if (lower.contains('soon') || lower.contains('expir')) {
    return soon.isEmpty
        ? 'Nothing in your kitchen is recorded as expiring within the next three days.'
        : 'Use ${soon.take(3).map((item) => item.name).join(', ')} soon based on the expiry dates in your kitchen.';
  }
  if (lower.contains('deficien') || lower.contains('diagnos')) {
    return 'TUM.me cannot diagnose a deficiency. I can summarize your logged intake, but a clinician and appropriate testing are needed for diagnosis.';
  }
  final available = inventory
      .where((item) => item.quantity > 0)
      .take(3)
      .toList();
  if (available.isEmpty) {
    return 'Your kitchen does not have enough recorded items for an inventory-based suggestion. Add what you have, then ask again.';
  }
  final expiryNote = soon.isEmpty
      ? ''
      : ' Prioritize ${soon.first.name}, which is recorded as expiring soon.';
  return 'You have logged ${protein.toStringAsFixed(1)} g protein today. Consider a meal using ${available.map((item) => item.name).join(', ')}.$expiryNote';
}

bool _sameDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;
