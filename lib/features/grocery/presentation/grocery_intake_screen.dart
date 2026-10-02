import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/feature_analytics.dart';
import '../../../core/config/app_capabilities.dart';
import '../../../core/widgets/demo_unavailable.dart';
import '../data/grocery_repository.dart';

class GroceryIntakeScreen extends ConsumerStatefulWidget {
  const GroceryIntakeScreen({super.key});

  @override
  ConsumerState<GroceryIntakeScreen> createState() =>
      _GroceryIntakeScreenState();
}

class _GroceryIntakeScreenState extends ConsumerState<GroceryIntakeScreen> {
  bool busy = false;

  Future<void> finish(List<GroceryItem> items) async {
    if (!AppCapabilities.groceryIntake) return;
    setState(() => busy = true);
    try {
      final groceries = ref.read(groceryRepositoryProvider);
      await groceries.intakePurchasedItems(items.map((item) => item.id));
      await ref
          .read(featureAnalyticsProvider)
          .record(FeatureEvent.groceryIntakeCompleted);
      if (mounted) context.go('/home/kitchen');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not complete grocery intake.')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!AppCapabilities.groceryIntake) {
      return Scaffold(
        appBar: AppBar(title: const Text('Grocery intake')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: DemoUnavailableCard(
              title: 'Unavailable in free demo',
              message:
                  'Purchased items stay on your grocery list. Add them to Kitchen manually.',
            ),
          ),
        ),
      );
    }
    final items = ref.watch(groceryItemsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Grocery intake')),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Could not load purchases.')),
        data: (all) {
          final purchased = all
              .where((item) => item.status == 'purchased')
              .toList();
          if (purchased.isEmpty) {
            return const Center(child: Text('No purchased items to add.'));
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Confirm these purchases. Existing kitchen matches receive a new batch; other items are added to the pantry.',
              ),
              const SizedBox(height: 16),
              for (final item in purchased)
                ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(item.name),
                  subtitle: Text('${item.quantity} ${item.unit}'),
                ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: busy ? null : () => finish(purchased),
                child: Text(busy ? 'Adding…' : 'Confirm kitchen intake'),
              ),
            ],
          );
        },
      ),
    );
  }
}
