import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_capabilities.dart';
import '../core/firebase/firebase_config.dart';
import '../core/firebase/messaging_service.dart';
import '../shared/design_system/app_strings.dart';
import 'router.dart';
import 'theme.dart';

class TUMmeApp extends ConsumerStatefulWidget {
  const TUMmeApp({required this.configuration, super.key});
  final FirebaseConfiguration configuration;

  @override
  ConsumerState<TUMmeApp> createState() => _TUMmeAppState();
}

class _TUMmeAppState extends ConsumerState<TUMmeApp> {
  final messengerKey = GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    if (AppCapabilities.notifications) {
      Future.microtask(
        () => ref
            .read(messagingServiceProvider)
            .restoreRegistrationIfAuthorized(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (AppCapabilities.notifications) {
      ref.listen(foregroundMessagesProvider, (_, next) {
        next.whenData((message) {
          final notification = message.notification;
          if (notification == null) return;
          messengerKey.currentState?.showSnackBar(
            SnackBar(
              content: Text(
                [notification.title, notification.body]
                    .whereType<String>()
                    .where((value) => value.isNotEmpty)
                    .join('\n'),
              ),
            ),
          );
        });
      });
    }
    final router = ref.watch(routerProvider(widget.configuration));
    return MaterialApp.router(
      title: AppStrings.appName,
      theme: AppTheme.light,
      routerConfig: router,
      scaffoldMessengerKey: messengerKey,
      debugShowCheckedModeBanner: widget.configuration.isDevelopment,
    );
  }
}
