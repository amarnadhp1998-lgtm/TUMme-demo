import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/grocery_repository.dart';

class GroceryScreen extends ConsumerStatefulWidget {
  const GroceryScreen({super.key});

  @override
  ConsumerState<GroceryScreen> createState() => _GroceryScreenState();
}

class _GroceryScreenState extends ConsumerState<GroceryScreen> {
  final name = TextEditingController();
  final quantity = TextEditingController(text: '1');
  String unit = 'item';
  bool busy = false;

  @override
  void dispose() {
    name.dispose();
    quantity.dispose();
    super.dispose();
  }

  Future<void> addItem() async {
    final itemName = name.text.trim();
    final amount = double.tryParse(quantity.text);
    if (itemName.isEmpty || amount == null || amount <= 0) {
      _message('Enter an item and a valid quantity.');
      return;
    }
    setState(() => busy = true);
    try {
      await ref
          .read(groceryRepositoryProvider)
          .add(name: itemName, quantity: amount, unit: unit);
      name.clear();
      quantity.text = '1';
    } catch (_) {
      if (mounted) _message('Could not add this item.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(groceryItemsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Grocery'),
        actions: [
          IconButton(
            tooltip: 'Shopping mode',
            onPressed: () => context.push('/grocery/shopping'),
            icon: const Icon(Icons.shopping_cart_checkout),
          ),
          items.maybeWhen(
            data: (values) {
              final checked = values.where((item) => item.checked).toList();
              return checked.isEmpty
                  ? const SizedBox.shrink()
                  : TextButton(
                      onPressed: busy
                          ? null
                          : () => ref
                                .read(groceryRepositoryProvider)
                                .clearChecked(checked.map((item) => item.id)),
                      child: const Text('Clear bought'),
                    );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: name,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: TextInputAction.done,
                    onSubmitted: busy ? null : (_) => addItem(),
                    decoration: const InputDecoration(
                      labelText: 'Add grocery item',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: quantity,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Qty'),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButton<String>(
                  value: unit,
                  items: const ['item', 'g', 'kg', 'ml', 'l']
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(),
                  onChanged: busy
                      ? null
                      : (value) => setState(() => unit = value!),
                ),
                IconButton(
                  onPressed: busy ? null : addItem,
                  tooltip: 'Add item',
                  icon: const Icon(Icons.add_circle),
                ),
              ],
            ),
          ),
          Expanded(
            child: items.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => Center(
                child: FilledButton.tonal(
                  onPressed: () => ref.invalidate(groceryItemsProvider),
                  child: const Text('Retry loading groceries'),
                ),
              ),
              data: (values) {
                final visible = values
                    .where((item) => item.status != 'dismissed')
                    .toList();
                return visible.isEmpty
                    ? const _EmptyGroceryList()
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 24),
                        itemCount: visible.length,
                        itemBuilder: (context, index) {
                          final item = visible[index];
                          if (item.status == 'suggested') {
                            return Card(
                              margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                              child: ListTile(
                                leading: const Icon(Icons.inventory_2_outlined),
                                title: Text(item.name),
                                subtitle: Text(
                                  '${_quantity(item.quantity)} ${item.unit} · ${item.reasonText ?? 'Suggested'}',
                                ),
                                trailing: Wrap(
                                  children: [
                                    IconButton(
                                      tooltip: 'Dismiss suggestion',
                                      icon: const Icon(Icons.close),
                                      onPressed: () => ref
                                          .read(groceryRepositoryProvider)
                                          .setStatus(item.id, 'dismissed'),
                                    ),
                                    IconButton(
                                      tooltip: 'Accept suggestion',
                                      icon: const Icon(Icons.check),
                                      onPressed: () => ref
                                          .read(groceryRepositoryProvider)
                                          .setStatus(item.id, 'accepted'),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          return Dismissible(
                            key: ValueKey(item.id),
                            direction: DismissDirection.endToStart,
                            background: Container(
                              color: Theme.of(
                                context,
                              ).colorScheme.errorContainer,
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 24),
                              child: const Icon(Icons.delete_outline),
                            ),
                            onDismissed: (_) => ref
                                .read(groceryRepositoryProvider)
                                .delete(item.id),
                            child: CheckboxListTile(
                              value: item.checked,
                              onChanged: (value) => ref
                                  .read(groceryRepositoryProvider)
                                  .setChecked(item.id, value ?? false),
                              title: Text(
                                item.name,
                                style: TextStyle(
                                  decoration: item.checked
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                              subtitle: Text(
                                '${_quantity(item.quantity)} ${item.unit}',
                              ),
                              secondary: Icon(
                                item.source == 'low_stock'
                                    ? Icons.inventory_2_outlined
                                    : Icons.drag_handle,
                              ),
                            ),
                          );
                        },
                      );
              },
            ),
          ),
        ],
      ),
    );
  }
}

String _quantity(double value) =>
    value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);

class _EmptyGroceryList extends StatelessWidget {
  const _EmptyGroceryList();

  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_cart_outlined, size: 56),
          SizedBox(height: 16),
          Text('Your grocery list is clear'),
          SizedBox(height: 8),
          Text('Add items above as you plan your next shop.'),
        ],
      ),
    ),
  );
}
