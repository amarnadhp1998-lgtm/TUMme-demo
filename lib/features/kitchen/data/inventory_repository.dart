import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return InventoryRepository(FirebaseAuth.instance, FirebaseFirestore.instance);
});

final inventoryProvider = StreamProvider<List<InventoryItem>>((ref) {
  return ref.watch(inventoryRepositoryProvider).watchItems();
});

final inventoryBatchesProvider =
    StreamProvider.family<List<InventoryBatch>, String>((ref, inventoryId) {
      return ref.watch(inventoryRepositoryProvider).watchBatches(inventoryId);
    });

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.storageLocation,
    required this.expiryDate,
    required this.foodId,
    required this.lowStockThreshold,
  });

  final String id;
  final String name;
  final double quantity;
  final String unit;
  final String storageLocation;
  final DateTime? expiryDate;
  final String? foodId;
  final double lowStockThreshold;

  bool get isLowStock =>
      quantity > 0 && lowStockThreshold > 0 && quantity <= lowStockThreshold;

  InventoryState get state {
    if (quantity <= 0) return InventoryState.out;
    if (expiryDate != null && expiryDate!.isBefore(DateTime.now())) {
      return InventoryState.expired;
    }
    if (expiryDate != null &&
        expiryDate!.isBefore(DateTime.now().add(const Duration(days: 3)))) {
      return InventoryState.expiresSoon;
    }
    if (isLowStock) return InventoryState.low;
    return InventoryState.ok;
  }

  factory InventoryItem.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    return InventoryItem(
      id: document.id,
      name: data['name'] as String? ?? '',
      quantity: (data['quantity'] as num?)?.toDouble() ?? 0,
      unit: data['unit'] as String? ?? 'item',
      storageLocation: data['storageLocation'] as String? ?? 'pantry',
      expiryDate: (data['expiryDate'] as Timestamp?)?.toDate(),
      foodId: data['foodId'] as String?,
      lowStockThreshold: (data['lowStockThreshold'] as num?)?.toDouble() ?? 0,
    );
  }
}

enum InventoryState { ok, low, expiresSoon, expired, out }

class InventoryBatch {
  const InventoryBatch({
    required this.id,
    required this.quantityInitial,
    required this.quantityRemaining,
    required this.unit,
    required this.expiryDate,
  });

  final String id;
  final double quantityInitial;
  final double quantityRemaining;
  final String unit;
  final DateTime? expiryDate;

  factory InventoryBatch.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    return InventoryBatch(
      id: document.id,
      quantityInitial: (data['quantityInitial'] as num?)?.toDouble() ?? 0,
      quantityRemaining: (data['quantityRemaining'] as num?)?.toDouble() ?? 0,
      unit: data['unit'] as String? ?? 'item',
      expiryDate: (data['expiryDate'] as Timestamp?)?.toDate(),
    );
  }
}

class ConsumptionResult {
  const ConsumptionResult({
    required this.consumed,
    required this.unresolved,
    required this.alreadyApplied,
  });
  final double consumed;
  final double unresolved;
  final bool alreadyApplied;
}

class InventoryRepository {
  const InventoryRepository(this.auth, this.firestore);

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;

  CollectionReference<Map<String, dynamic>> get collection {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw StateError('No authenticated user.');
    return firestore.collection('users').doc(uid).collection('inventory');
  }

  Stream<List<InventoryItem>> watchItems() => collection
      .orderBy('name')
      .snapshots()
      .map(
        (snapshot) => snapshot.docs.map(InventoryItem.fromDocument).toList(),
      );

  Stream<List<InventoryBatch>> watchBatches(String inventoryId) => collection
      .doc(inventoryId)
      .collection('batches')
      .snapshots()
      .map((snapshot) {
        final batches = snapshot.docs.map(InventoryBatch.fromDocument).toList();
        batches.sort((a, b) {
          if (a.expiryDate == null) return 1;
          if (b.expiryDate == null) return -1;
          return a.expiryDate!.compareTo(b.expiryDate!);
        });
        return batches;
      });

  Future<void> save({
    String? id,
    required String name,
    required double quantity,
    required String unit,
    required String storageLocation,
    DateTime? expiryDate,
    String? foodId,
    required double lowStockThreshold,
    String source = 'manual',
  }) async {
    final reference = id == null ? collection.doc() : collection.doc(id);
    final batch = firestore.batch();
    batch.set(reference, {
      'name': name.trim(),
      'quantity': quantity,
      'unit': unit,
      'storageLocation': storageLocation,
      'expiryDate': expiryDate == null ? null : Timestamp.fromDate(expiryDate),
      'foodId': foodId,
      'lowStockThreshold': lowStockThreshold,
      'updatedAt': FieldValue.serverTimestamp(),
      if (id == null) 'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    if (id == null) {
      batch.set(reference.collection('batches').doc(), {
        'quantityInitial': quantity,
        'quantityRemaining': quantity,
        'unit': unit,
        'purchaseDate': null,
        'expiryDate': expiryDate == null
            ? null
            : Timestamp.fromDate(expiryDate),
        'source': source,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }

  Future<void> addBatch({
    required String inventoryId,
    required double quantity,
    required String unit,
    DateTime? expiryDate,
    String source = 'grocery_intake',
  }) async {
    final itemRef = collection.doc(inventoryId);
    final batchRef = itemRef.collection('batches').doc();
    await firestore.runTransaction((transaction) async {
      final item = await transaction.get(itemRef);
      if (!item.exists) throw StateError('Inventory item no longer exists.');
      final current = (item.data()?['quantity'] as num?)?.toDouble() ?? 0;
      final currentExpiry = (item.data()?['expiryDate'] as Timestamp?)
          ?.toDate();
      final earliest = expiryDate == null
          ? currentExpiry
          : currentExpiry == null || expiryDate.isBefore(currentExpiry)
          ? expiryDate
          : currentExpiry;
      transaction.set(batchRef, {
        'quantityInitial': quantity,
        'quantityRemaining': quantity,
        'unit': unit,
        'purchaseDate': FieldValue.serverTimestamp(),
        'expiryDate': expiryDate == null
            ? null
            : Timestamp.fromDate(expiryDate),
        'source': source,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.update(itemRef, {
        'quantity': current + quantity,
        'expiryDate': earliest == null ? null : Timestamp.fromDate(earliest),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<ConsumptionResult> consumeFefo(
    String inventoryId,
    double amount, {
    required String idempotencyKey,
    String? mealId,
    String? mealLineId,
  }) async {
    if (amount <= 0) throw ArgumentError.value(amount, 'amount');
    final itemRef = collection.doc(inventoryId);
    final ledgerRef = itemRef.collection('ledger').doc(idempotencyKey);
    final snapshot = await itemRef.collection('batches').get();
    final references = snapshot.docs.toList()
      ..sort((a, b) {
        final aDate = (a.data()['expiryDate'] as Timestamp?)?.toDate();
        final bDate = (b.data()['expiryDate'] as Timestamp?)?.toDate();
        if (aDate == null) return 1;
        if (bDate == null) return -1;
        return aDate.compareTo(bDate);
      });

    return firestore.runTransaction((transaction) async {
      final priorLedger = await transaction.get(ledgerRef);
      if (priorLedger.exists) {
        final data = priorLedger.data()!;
        return ConsumptionResult(
          consumed: ((data['delta'] as num?)?.toDouble() ?? 0).abs(),
          unresolved: (data['unresolved'] as num?)?.toDouble() ?? 0,
          alreadyApplied: true,
        );
      }
      final itemSnapshot = await transaction.get(itemRef);
      final freshBatches = <DocumentSnapshot<Map<String, dynamic>>>[];
      for (final reference in references) {
        freshBatches.add(await transaction.get(reference.reference));
      }
      var remaining = amount;
      var consumed = 0.0;
      final allocations = <Map<String, dynamic>>[];
      DateTime? earliestExpiry;
      var totalAfter = 0.0;
      for (final fresh in freshBatches) {
        final data = fresh.data()!;
        final available = (data['quantityRemaining'] as num?)?.toDouble() ?? 0;
        final deduction = remaining < available ? remaining : available;
        final after = available - deduction;
        if (deduction > 0) {
          transaction.update(fresh.reference, {
            'quantityRemaining': after,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          remaining -= deduction;
          consumed += deduction;
          allocations.add({'batchId': fresh.id, 'amount': deduction});
        }
        totalAfter += after;
        final expiry = (data['expiryDate'] as Timestamp?)?.toDate();
        if (after > 0 &&
            expiry != null &&
            (earliestExpiry == null || expiry.isBefore(earliestExpiry))) {
          earliestExpiry = expiry;
        }
      }
      transaction.update(itemRef, {
        'quantity': totalAfter,
        'expiryDate': earliestExpiry == null
            ? null
            : Timestamp.fromDate(earliestExpiry),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      transaction.set(ledgerRef, {
        'type': 'consume',
        'delta': -consumed,
        'unit': itemSnapshot.data()?['unit'] ?? 'item',
        'mealId': mealId,
        'mealLineId': mealLineId,
        'idempotencyKey': idempotencyKey,
        'allocations': allocations,
        'unresolved': remaining,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return ConsumptionResult(
        consumed: consumed,
        unresolved: remaining,
        alreadyApplied: false,
      );
    });
  }

  Future<void> restoreMealDeductions(String mealId) async {
    final items = await collection.get();
    final ledgerDocuments = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    for (final item in items.docs) {
      final matches = await item.reference
          .collection('ledger')
          .where('mealId', isEqualTo: mealId)
          .get();
      ledgerDocuments.addAll(matches.docs);
    }
    for (final ledger in ledgerDocuments) {
      if (ledger.data()['type'] != 'consume') continue;
      final itemRef = ledger.reference.parent.parent;
      if (itemRef == null) continue;
      final allocations =
          (ledger.data()['allocations'] as List<dynamic>? ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList();
      await firestore.runTransaction((transaction) async {
        final freshLedger = await transaction.get(ledger.reference);
        if (!freshLedger.exists || freshLedger.data()?['type'] != 'consume')
          return;
        final itemSnapshot = await transaction.get(itemRef);
        final restorableBatches =
            <
              ({double amount, DocumentSnapshot<Map<String, dynamic>> snapshot})
            >[];
        for (final allocation in allocations) {
          final batchId = allocation['batchId'] as String?;
          final amount = (allocation['amount'] as num?)?.toDouble() ?? 0;
          if (batchId == null || amount <= 0) continue;
          final snapshot = await transaction.get(
            itemRef.collection('batches').doc(batchId),
          );
          restorableBatches.add((amount: amount, snapshot: snapshot));
        }
        var restored = 0.0;
        DateTime? earliestExpiry =
            (itemSnapshot.data()?['expiryDate'] as Timestamp?)?.toDate();
        for (final restorable in restorableBatches) {
          final amount = restorable.amount;
          final batchSnapshot = restorable.snapshot;
          if (!batchSnapshot.exists) continue;
          final data = batchSnapshot.data()!;
          final current = (data['quantityRemaining'] as num?)?.toDouble() ?? 0;
          final initial =
              (data['quantityInitial'] as num?)?.toDouble() ?? current;
          final next = (current + amount).clamp(0, initial).toDouble();
          restored += next - current;
          final expiry = (data['expiryDate'] as Timestamp?)?.toDate();
          if (next > 0 &&
              expiry != null &&
              (earliestExpiry == null || expiry.isBefore(earliestExpiry))) {
            earliestExpiry = expiry;
          }
          transaction.update(batchSnapshot.reference, {
            'quantityRemaining': next,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        final currentTotal =
            (itemSnapshot.data()?['quantity'] as num?)?.toDouble() ?? 0;
        transaction.update(itemRef, {
          'quantity': currentTotal + restored,
          'expiryDate': earliestExpiry == null
              ? null
              : Timestamp.fromDate(earliestExpiry),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        transaction.update(ledger.reference, {
          'type': 'restore',
          'restoredAt': FieldValue.serverTimestamp(),
        });
      });
    }
  }

  Future<void> delete(String id) => collection.doc(id).delete();
}
