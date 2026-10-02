import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_capabilities.dart';

final groceryRepositoryProvider = Provider<GroceryRepository>((ref) {
  return GroceryRepository(
    FirebaseAuth.instance,
    FirebaseFirestore.instance,
    FirebaseFunctions.instanceFor(region: 'asia-south1'),
  );
});

final groceryItemsProvider = StreamProvider<List<GroceryItem>>((ref) {
  return ref.watch(groceryRepositoryProvider).watchItems();
});

class GroceryItem {
  const GroceryItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.unit,
    required this.checked,
    required this.source,
    required this.sourceInventoryId,
    required this.status,
    required this.reasonText,
  });

  final String id;
  final String name;
  final double quantity;
  final String unit;
  final bool checked;
  final String source;
  final String? sourceInventoryId;
  final String status;
  final String? reasonText;

  factory GroceryItem.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> document,
  ) {
    final data = document.data();
    return GroceryItem(
      id: document.id,
      name: data['name'] as String? ?? '',
      quantity: (data['quantity'] as num?)?.toDouble() ?? 1,
      unit: data['unit'] as String? ?? 'item',
      checked: data['checked'] == true,
      source: data['source'] as String? ?? 'manual',
      sourceInventoryId: data['sourceInventoryId'] as String?,
      status:
          data['status'] as String? ??
          (data['checked'] == true ? 'purchased' : 'accepted'),
      reasonText: data['reasonText'] as String?,
    );
  }
}

class GroceryRepository {
  const GroceryRepository(this.auth, this.firestore, this.functions);

  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final FirebaseFunctions functions;

  CollectionReference<Map<String, dynamic>> get collection {
    final uid = auth.currentUser?.uid;
    if (uid == null) throw StateError('No authenticated user.');
    return firestore.collection('users').doc(uid).collection('groceryItems');
  }

  Stream<List<GroceryItem>> watchItems() => collection
      .orderBy('createdAt')
      .snapshots()
      .map((snapshot) => snapshot.docs.map(GroceryItem.fromDocument).toList());

  Future<void> add({
    required String name,
    required double quantity,
    required String unit,
  }) => collection.add({
    'name': name.trim(),
    'quantity': quantity,
    'unit': unit,
    'checked': false,
    'source': 'manual',
    'sourceInventoryId': null,
    'status': 'accepted',
    'reasonText': 'Added manually',
    'createdAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> addLowStockSuggestion({
    required String inventoryId,
    required String name,
    required double quantity,
    required String unit,
  }) async {
    final reference = collection.doc('inventory_$inventoryId');
    await firestore.runTransaction((transaction) async {
      final existing = await transaction.get(reference);
      final data = <String, dynamic>{
        'name': name.trim(),
        'quantity': quantity,
        'unit': unit,
        'checked': false,
        'source': 'low_stock',
        'sourceInventoryId': inventoryId,
        'status': existing.data()?['status'] == 'dismissed'
            ? 'dismissed'
            : 'suggested',
        'reasonText': 'Running low in your kitchen',
        'updatedAt': FieldValue.serverTimestamp(),
        if (!existing.exists) 'createdAt': FieldValue.serverTimestamp(),
      };
      if (existing.exists) {
        transaction.update(reference, data);
      } else {
        transaction.set(reference, data);
      }
    });
  }

  Future<void> setChecked(String id, bool value) => collection.doc(id).update({
    'checked': value,
    'status': value ? 'purchased' : 'accepted',
    'updatedAt': FieldValue.serverTimestamp(),
  });

  Future<void> setStatus(String id, String status) =>
      collection.doc(id).update({
        'status': status,
        'checked': status == 'purchased',
        'updatedAt': FieldValue.serverTimestamp(),
      });

  Future<void> delete(String id) => collection.doc(id).delete();

  Future<int> intakePurchasedItems(Iterable<String> ids) async {
    if (!AppCapabilities.groceryIntake) {
      throw UnsupportedError('Grocery intake is unavailable in the free demo.');
    }
    final itemIds = ids.toSet().toList(growable: false);
    if (itemIds.isEmpty) return 0;
    final result = await functions.httpsCallable('intakePurchasedItems').call({
      'itemIds': itemIds,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return (data['processed'] as num?)?.toInt() ?? 0;
  }

  Future<void> clearChecked(Iterable<String> ids) async {
    final batch = firestore.batch();
    for (final id in ids) {
      batch.delete(collection.doc(id));
    }
    await batch.commit();
  }
}
