import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_capabilities.dart';

final privacyRepositoryProvider = Provider<PrivacyRepository>((ref) {
  return PrivacyRepository(
    FirebaseFunctions.instanceFor(region: 'asia-south1'),
  );
});

class PrivacyRepository {
  const PrivacyRepository(this.functions);
  final FirebaseFunctions functions;

  Future<String> exportMyData() async {
    if (!AppCapabilities.dataExportAndAccountDeletion) {
      throw UnsupportedError('Data export is unavailable in the free demo.');
    }
    final result = await functions
        .httpsCallable('exportMyData')
        .call<Map<String, dynamic>>();
    return const JsonEncoder.withIndent('  ').convert(result.data);
  }

  Future<void> deleteMyAccount() async {
    if (!AppCapabilities.dataExportAndAccountDeletion) {
      throw UnsupportedError(
        'Account deletion is unavailable in the free demo.',
      );
    }
    await functions.httpsCallable('deleteMyAccount').call<void>({
      'confirmation': 'DELETE',
    });
  }
}
