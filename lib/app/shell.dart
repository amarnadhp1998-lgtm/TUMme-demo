import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/firebase/sync_status.dart';
import '../shared/design_system/app_strings.dart';

class AppShell extends ConsumerWidget {
  const AppShell({required this.child, super.key});
  final Widget child;

  static const destinations = [
    (label: AppStrings.today, icon: Icons.today_outlined, path: '/home/today'),
    (
      label: AppStrings.meals,
      icon: Icons.restaurant_outlined,
      path: '/home/meals',
    ),
    (
      label: AppStrings.kitchen,
      icon: Icons.kitchen_outlined,
      path: '/home/kitchen',
    ),
    (
      label: AppStrings.grocery,
      icon: Icons.shopping_basket_outlined,
      path: '/home/grocery',
    ),
    (
      label: AppStrings.health,
      icon: Icons.favorite_outline,
      path: '/home/health',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = GoRouterState.of(context).uri.path;
    final index = destinations.indexWhere((item) => item.path == current);
    final syncStatus = ref.watch(firestoreSyncStatusProvider).value;
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return Scaffold(
      body: Column(
        children: [
          if (syncStatus == FirestoreSyncStatus.cached)
            const _SyncBanner(
              icon: Icons.cloud_off_outlined,
              message: 'Offline — showing saved data',
            )
          else if (syncStatus == FirestoreSyncStatus.syncing)
            const _SyncBanner(
              icon: Icons.cloud_upload_outlined,
              message: 'Saving changes…',
            ),
          Expanded(child: child),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/coach'),
        icon: const Icon(Icons.auto_awesome_outlined),
        label: const Text(AppStrings.askTum),
      ),
      bottomNavigationBar: NavigationBar(
        labelBehavior: largeText
            ? NavigationDestinationLabelBehavior.onlyShowSelected
            : NavigationDestinationLabelBehavior.alwaysShow,
        selectedIndex: index < 0 ? 0 : index,
        onDestinationSelected: (selected) =>
            context.go(destinations[selected].path),
        destinations: [
          for (final item in destinations)
            NavigationDestination(icon: Icon(item.icon), label: item.label),
        ],
      ),
    );
  }
}

class _SyncBanner extends StatelessWidget {
  const _SyncBanner({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          width: double.infinity,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18),
                const SizedBox(width: 8),
                Flexible(child: Text(message)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
