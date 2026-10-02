import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_repository.dart';
import '../../../shared/design_system/app_strings.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final formKey = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  bool creating = false;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!formKey.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final repository = ref.read(authRepositoryProvider);
      if (creating) {
        await repository.createAccount(email.text.trim(), password.text);
      } else {
        await repository.signIn(email.text.trim(), password.text);
      }
    } on FirebaseAuthException catch (error) {
      if (mounted) showError(_authErrorText(error.code));
    } catch (_) {
      if (mounted) showError('Sign-in is unavailable. Please try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resetPassword() async {
    if (email.text.trim().isEmpty) {
      showError('Enter your email address first.');
      return;
    }
    setState(() => busy = true);
    try {
      await ref.read(authRepositoryProvider).resetPassword(email.text.trim());
      if (mounted) {
        showMessage('If this email has an account, a reset link will arrive.');
      }
    } catch (_) {
      if (mounted) {
        showError('Password reset is unavailable. Please try again.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> signInWithProvider(Future<void> Function() signIn) async {
    setState(() => busy = true);
    try {
      await signIn();
    } on FirebaseAuthException catch (error) {
      if (mounted) showError(_authErrorText(error.code));
    } catch (_) {
      if (mounted) showError('Provider sign-in is unavailable. Try again.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void showError(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
  void showMessage(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  String _authErrorText(String code) => switch (code) {
    'invalid-email' => 'Enter a valid email address.',
    'weak-password' => 'Choose a stronger password.',
    'email-already-in-use' => 'This email already has an account.',
    'invalid-credential' ||
    'wrong-password' ||
    'user-not-found' => 'The email or password is incorrect.',
    'too-many-requests' => 'Too many attempts. Try again later.',
    'web-context-cancelled' ||
    'popup-closed-by-user' ||
    'canceled' => 'Sign-in was cancelled.',
    'operation-not-allowed' =>
      'This sign-in provider is not enabled for this Firebase project.',
    'account-exists-with-different-credential' =>
      'An account already exists with this email. Use its original sign-in method.',
    _ => 'Sign-in is unavailable. Please try again.',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  AppStrings.appName,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 8),
                Text(creating ? AppStrings.createAccount : AppStrings.signIn),
                const SizedBox(height: 24),
                Form(
                  key: formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: email,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: AppStrings.email,
                        ),
                        validator: (value) =>
                            value == null || !value.contains('@')
                            ? 'Enter a valid email address.'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: password,
                        obscureText: true,
                        autofillHints: [
                          creating
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        decoration: const InputDecoration(
                          labelText: AppStrings.password,
                        ),
                        validator: (value) => value == null || value.length < 6
                            ? 'Use at least six characters.'
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: busy ? null : submit,
                  child: busy
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          creating
                              ? AppStrings.createAccount
                              : AppStrings.signIn,
                        ),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setState(() => creating = !creating),
                  child: Text(
                    creating ? AppStrings.signIn : AppStrings.createAccount,
                  ),
                ),
                TextButton(
                  onPressed: busy ? null : resetPassword,
                  child: const Text(AppStrings.resetPassword),
                ),
                const Divider(height: 32),
                OutlinedButton.icon(
                  onPressed: busy
                      ? null
                      : () => signInWithProvider(
                          ref.read(authRepositoryProvider).signInWithGoogle,
                        ),
                  icon: const Icon(Icons.account_circle_outlined),
                  label: const Text('Continue with Google'),
                ),
                if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) ...[
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: busy
                        ? null
                        : () => signInWithProvider(
                            ref.read(authRepositoryProvider).signInWithApple,
                          ),
                    icon: const Icon(Icons.apple),
                    label: const Text('Continue with Apple'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
