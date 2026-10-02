import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/auth/auth_repository.dart';
import '../core/widgets/async_status.dart';
import '../shared/design_system/app_strings.dart';

class SessionSplashScreen extends ConsumerWidget {
  const SessionSplashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);
    final user = auth.value;
    final document = user == null
        ? null
        : ref.watch(userDocumentProvider(user.uid));
    if (auth.hasError || document?.hasError == true) {
      return Scaffold(
        body: ErrorState(
          message: 'We could not restore your session.',
          onRetry: () {
            ref.invalidate(authStateProvider);
            if (user != null) ref.invalidate(userDocumentProvider(user.uid));
          },
        ),
      );
    }
    return const Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(AppStrings.appName, style: TextStyle(fontSize: 28)),
          SizedBox(height: 20),
          LoadingState(),
        ],
      ),
    );
  }
}
