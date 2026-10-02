import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_repository.dart';

class EmailVerificationScreen extends ConsumerStatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  ConsumerState<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState
    extends ConsumerState<EmailVerificationScreen> {
  bool busy = false;

  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('That did not work. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = ref.read(authRepositoryProvider);
    final email = repository.auth.currentUser?.email ?? 'your email address';
    return Scaffold(
      appBar: AppBar(title: const Text('Verify your email')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.mark_email_unread_outlined, size: 56),
                const SizedBox(height: 20),
                Text(
                  'Check your inbox',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(
                  'We sent a verification link to $email. Open it, then return here.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                          final verified = await repository
                              .refreshEmailVerification();
                          if (!context.mounted) return;
                          if (!verified) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Email is not verified yet.'),
                              ),
                            );
                          }
                        }),
                  child: Text(busy ? 'Checking…' : 'I verified my email'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => run(repository.resendEmailVerification),
                  child: const Text('Resend verification email'),
                ),
                TextButton(
                  onPressed: busy ? null : () => run(repository.signOut),
                  child: const Text('Use another account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
