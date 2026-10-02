import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_capabilities.dart';
import '../data/grocery_repository.dart';

class ShoppingScreen extends ConsumerWidget {
  const ShoppingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(groceryItemsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Shopping mode')),
      body: items.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Could not load shopping list.')),
        data: (all) {
          final active = all
              .where(
                (item) =>
                    item.status == 'accepted' || item.status == 'purchased',
              )
              .toList();
          final purchased = active
              .where((item) => item.status == 'purchased')
              .length;
          if (active.isEmpty) {
            return const Center(
              child: Text('Accept or add grocery items first.'),
            );
          }
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Semantics(
                  label: 'Shopping progress',
                  value: '$purchased of ${active.length} purchased',
                  child: LinearProgressIndicator(
                    value: purchased / active.length,
                  ),
                ),
              ),
              Text('$purchased of ${active.length} purchased'),
              Expanded(
                child: ListView.builder(
                  itemCount: active.length,
                  itemBuilder: (context, index) {
                    final item = active[index];
                    return CheckboxListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      value: item.status == 'purchased',
                      onChanged: (value) => ref
                          .read(groceryRepositoryProvider)
                          .setStatus(
                            item.id,
                            value == true ? 'purchased' : 'accepted',
                          ),
                      title: Text(
                        item.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      subtitle: Text('${item.quantity} ${item.unit}'),
                    );
                  },
                ),
              ),
              SafeArea(
                minimum: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: purchased == 0 || !AppCapabilities.groceryIntake
                      ? null
                      : () => context.push('/grocery/intake'),
                  icon: Icon(
                    AppCapabilities.groceryIntake
                        ? Icons.kitchen_outlined
                        : Icons.lock_outline,
                  ),
                  label: Text(
                    AppCapabilities.groceryIntake
                        ? 'Finish and add purchases to Kitchen'
                        : 'Kitchen intake unavailable in free demo',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
