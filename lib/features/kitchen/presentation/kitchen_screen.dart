import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/inventory_repository.dart';
import '../../grocery/data/grocery_repository.dart';

class KitchenScreen extends ConsumerWidget {
  const KitchenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventory = ref.watch(inventoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Kitchen')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/kitchen/add'),
        icon: const Icon(Icons.add),
        label: const Text('Add item'),
      ),
      body: inventory.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: FilledButton.tonal(
            onPressed: () => ref.invalidate(inventoryProvider),
            child: const Text('Retry loading kitchen'),
          ),
        ),
        data: (items) => items.isEmpty
            ? const _EmptyKitchen()
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final expiry = item.expiryDate;
                  return ListTile(
                    leading: const CircleAvatar(
                      child: Icon(Icons.kitchen_outlined),
                    ),
                    title: Text(item.name),
                    subtitle: Text(
                      '${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 1)} ${item.unit} · ${item.storageLocation}'
                      '${expiry == null ? '' : ' · expires ${_date(expiry)}'}',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (item.state != InventoryState.ok)
                          Chip(label: Text(_stateLabel(item.state))),
                        if (item.isLowStock || item.state == InventoryState.out)
                          IconButton(
                            tooltip: 'Add grocery suggestion',
                            icon: const Icon(Icons.add_shopping_cart_outlined),
                            onPressed: () async {
                              final target = item.lowStockThreshold > 0
                                  ? item.lowStockThreshold
                                  : 1.0;
                              final amount = (target - item.quantity)
                                  .clamp(0.0, double.infinity)
                                  .toDouble();
                              try {
                                await ref
                                    .read(groceryRepositoryProvider)
                                    .addLowStockSuggestion(
                                      inventoryId: item.id,
                                      name: item.name,
                                      quantity: amount > 0 ? amount : target,
                                      unit: item.unit,
                                    );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Added to grocery list.'),
                                    ),
                                  );
                                }
                              } catch (_) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Could not add grocery suggestion.',
                                      ),
                                    ),
                                  );
                                }
                              }
                            },
                          ),
                        const Icon(Icons.chevron_right),
                      ],
                    ),
                    onTap: () =>
                        context.push('/kitchen/${item.id}', extra: item),
                  );
                },
              ),
      ),
    );
  }
}

String _stateLabel(InventoryState state) => switch (state) {
  InventoryState.expiresSoon => 'Soon',
  InventoryState.expired => 'Expired',
  InventoryState.out => 'Out',
  InventoryState.low => 'Low',
  InventoryState.ok => 'OK',
};

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

class _EmptyKitchen extends StatelessWidget {
  const _EmptyKitchen();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, size: 56),
          SizedBox(height: 16),
          Text('Your kitchen is empty'),
          SizedBox(height: 8),
          Text('Add what you have so TUM.me can help you use it in time.'),
        ],
      ),
    ),
  );
}
