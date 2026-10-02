import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/design_system/app_strings.dart';

class EmptyFeatureScreen extends StatelessWidget {
  const EmptyFeatureScreen({required this.title, super.key});
  final String title;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: [
        IconButton(
          tooltip: AppStrings.settings,
          onPressed: () => context.push('/settings'),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 48),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            const Text(AppStrings.emptyState, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}
