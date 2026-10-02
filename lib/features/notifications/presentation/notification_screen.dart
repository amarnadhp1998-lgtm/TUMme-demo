import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_capabilities.dart';
import '../../../core/widgets/async_status.dart';
import '../../../core/widgets/demo_unavailable.dart';
import '../data/notification_repository.dart';

class NotificationScreen extends ConsumerWidget {
  const NotificationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!AppCapabilities.notifications) {
      return Scaffold(
        appBar: AppBar(title: const Text('Notifications')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: DemoUnavailableCard(
              title: 'Unavailable in free demo',
              message:
                  'Scheduled alerts and push notifications require the deployed backend.',
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: ref
          .watch(notificationsProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => ErrorState(
              message: 'Could not load notifications.',
              onRetry: () => ref.invalidate(notificationsProvider),
            ),
            data: (values) {
              final visible = values.where((value) => value.isVisible).toList();
              if (visible.isEmpty) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.notifications_none_outlined, size: 56),
                        SizedBox(height: 16),
                        Text('No notifications yet'),
                        SizedBox(height: 8),
                        Text(
                          'Expiry, low-stock, hydration, meal, and weekly alerts will appear here.',
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(notificationsProvider),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                  itemCount: visible.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final value = visible[index];
                    return Card(
                      color: value.isRead
                          ? null
                          : Theme.of(context).colorScheme.secondaryContainer,
                      child: ListTile(
                        leading: Icon(_icon(value.type)),
                        title: Text(value.title),
                        subtitle: Text(
                          '${value.body}\n${_timeLabel(value.createdAt)}',
                        ),
                        isThreeLine: true,
                        trailing: value.isRead
                            ? null
                            : const Icon(Icons.circle, size: 10),
                        onTap: () async {
                          if (!value.isRead) {
                            await ref
                                .read(notificationRepositoryProvider)
                                .markRead(value.id);
                          }
                          if (context.mounted) context.go(value.route);
                        },
                      ),
                    );
                  },
                ),
              );
            },
          ),
    );
  }
}

IconData _icon(String type) => switch (type) {
  'expiry' => Icons.event_busy_outlined,
  'low_stock' => Icons.shopping_basket_outlined,
  'hydration' => Icons.water_drop_outlined,
  'meal' => Icons.restaurant_outlined,
  'weekly_summary' => Icons.insights_outlined,
  _ => Icons.notifications_outlined,
};

String _timeLabel(DateTime value) {
  final local = value.toLocal();
  final minute = local.minute.toString().padLeft(2, '0');
  return '${local.day}/${local.month}/${local.year} · ${local.hour}:$minute';
}
