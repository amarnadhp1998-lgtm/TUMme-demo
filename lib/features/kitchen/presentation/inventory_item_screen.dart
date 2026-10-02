import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/inventory_repository.dart';
import '../../meals/domain/food_catalog.dart';

class InventoryItemScreen extends ConsumerStatefulWidget {
  const InventoryItemScreen({this.item, super.key});
  final InventoryItem? item;

  @override
  ConsumerState<InventoryItemScreen> createState() =>
      _InventoryItemScreenState();
}

class _InventoryItemScreenState extends ConsumerState<InventoryItemScreen> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name;
  late final TextEditingController quantity;
  late String unit;
  late String location;
  String? foodId;
  DateTime? expiryDate;
  bool busy = false;
  final consumeAmount = TextEditingController();
  late final TextEditingController lowStockThreshold;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    name = TextEditingController(text: item?.name ?? '');
    quantity = TextEditingController(text: item?.quantity.toString() ?? '1');
    unit = item?.unit ?? 'item';
    location = item?.storageLocation ?? 'pantry';
    expiryDate = item?.expiryDate;
    foodId = item?.foodId;
    lowStockThreshold = TextEditingController(
      text: item?.lowStockThreshold.toString() ?? '0',
    );
  }

  @override
  void dispose() {
    name.dispose();
    quantity.dispose();
    consumeAmount.dispose();
    lowStockThreshold.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await ref
          .read(inventoryRepositoryProvider)
          .save(
            id: widget.item?.id,
            name: name.text,
            quantity: double.parse(quantity.text),
            unit: unit,
            storageLocation: location,
            expiryDate: expiryDate,
            foodId: foodId,
            lowStockThreshold: double.parse(lowStockThreshold.text),
          );
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) _message('Could not save this item.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove() async {
    setState(() => busy = true);
    try {
      await ref.read(inventoryRepositoryProvider).delete(widget.item!.id);
      if (mounted) context.pop();
    } catch (_) {
      if (mounted) _message('Could not delete this item.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.item == null ? 'Add kitchen item' : 'Edit item'),
      actions: [
        if (widget.item != null)
          IconButton(
            onPressed: busy ? null : remove,
            tooltip: 'Delete item',
            icon: const Icon(Icons.delete_outline),
          ),
      ],
    ),
    body: Form(
      key: formKey,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextFormField(
            controller: name,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Food or product'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Enter an item name.'
                : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String?>(
            initialValue: foodId,
            decoration: const InputDecoration(
              labelText: 'Canonical food match',
              helperText: 'Enables exact meal-to-kitchen matching.',
            ),
            items: [
              const DropdownMenuItem<String?>(
                value: null,
                child: Text('Not matched'),
              ),
              for (final food in developmentFoodCatalog)
                DropdownMenuItem<String?>(
                  value: food.id,
                  child: Text(food.name),
                ),
            ],
            onChanged: busy
                ? null
                : (value) => setState(() {
                    foodId = value;
                    if (value != null && name.text.trim().isEmpty) {
                      name.text = developmentFoodCatalog
                          .firstWhere((food) => food.id == value)
                          .name;
                    }
                  }),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: quantity,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Quantity'),
            validator: (value) {
              final parsed = double.tryParse(value ?? '');
              return parsed == null || parsed <= 0
                  ? 'Enter a valid quantity.'
                  : null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: lowStockThreshold,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Low-stock alert ($unit)',
              helperText: 'Use 0 to turn suggestions off.',
            ),
            validator: (value) {
              final parsed = double.tryParse(value ?? '');
              return parsed == null || parsed < 0
                  ? 'Enter zero or a positive quantity.'
                  : null;
            },
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: unit,
            decoration: const InputDecoration(labelText: 'Unit'),
            items: const ['item', 'g', 'kg', 'ml', 'l']
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: busy ? null : (value) => setState(() => unit = value!),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: location,
            decoration: const InputDecoration(labelText: 'Stored in'),
            items: const ['pantry', 'fridge', 'freezer']
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: busy
                ? null
                : (value) => setState(() => location = value!),
          ),
          const SizedBox(height: 16),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Expiry date'),
            subtitle: Text(
              expiryDate == null ? 'Not set' : _format(expiryDate!),
            ),
            trailing: const Icon(Icons.calendar_today_outlined),
            onTap: busy
                ? null
                : () async {
                    final selected = await showDatePicker(
                      context: context,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 3650)),
                      initialDate: expiryDate ?? DateTime.now(),
                    );
                    if (selected != null) setState(() => expiryDate = selected);
                  },
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: busy ? null : save,
            child: Text(busy ? 'Saving…' : 'Save item'),
          ),
          if (widget.item != null) ...[
            const SizedBox(height: 28),
            Text('Batches', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            ref
                .watch(inventoryBatchesProvider(widget.item!.id))
                .when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => const Text('Could not load batches.'),
                  data: (batches) => batches.isEmpty
                      ? const Text('This older item has no batch records yet.')
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Card(
                              child: Column(
                                children: [
                                  for (
                                    var index = 0;
                                    index < batches.length;
                                    index++
                                  ) ...[
                                    ListTile(
                                      title: Text(
                                        '${batches[index].quantityRemaining.toStringAsFixed(1)} ${batches[index].unit} remaining',
                                      ),
                                      subtitle: Text(
                                        batches[index].expiryDate == null
                                            ? 'No expiry date'
                                            : 'Expires ${_format(batches[index].expiryDate!)}',
                                      ),
                                    ),
                                    if (index != batches.length - 1)
                                      const Divider(height: 1),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: consumeAmount,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: 'Amount used (${widget.item!.unit})',
                              ),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.tonal(
                              onPressed: busy
                                  ? null
                                  : () async {
                                      final amount = double.tryParse(
                                        consumeAmount.text,
                                      );
                                      if (amount == null || amount <= 0) {
                                        _message('Enter a valid amount.');
                                        return;
                                      }
                                      setState(() => busy = true);
                                      try {
                                        final result = await ref
                                            .read(inventoryRepositoryProvider)
                                            .consumeFefo(
                                              widget.item!.id,
                                              amount,
                                              idempotencyKey:
                                                  'manual-${DateTime.now().microsecondsSinceEpoch}',
                                            );
                                        if (mounted) {
                                          consumeAmount.clear();
                                          final suffix = result.unresolved > 0
                                              ? ' ${result.unresolved.toStringAsFixed(1)} could not be deducted.'
                                              : '';
                                          _message(
                                            'Used ${result.consumed.toStringAsFixed(1)} ${widget.item!.unit}.$suffix',
                                          );
                                        }
                                      } catch (_) {
                                        if (mounted) {
                                          _message('Could not update stock.');
                                        }
                                      } finally {
                                        if (mounted) {
                                          setState(() => busy = false);
                                        }
                                      }
                                    },
                              child: const Text('Use earliest-expiring stock'),
                            ),
                          ],
                        ),
                ),
          ],
        ],
      ),
    ),
  );
}

String _format(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
