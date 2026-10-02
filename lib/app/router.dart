import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/auth/auth_repository.dart';
import '../core/firebase/firebase_config.dart';
import '../features/onboarding/presentation/onboarding_placeholder.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/kitchen/data/inventory_repository.dart';
import '../features/kitchen/presentation/inventory_item_screen.dart';
import '../features/kitchen/presentation/kitchen_screen.dart';
import '../features/grocery/presentation/grocery_screen.dart';
import '../features/grocery/presentation/shopping_screen.dart';
import '../features/grocery/presentation/grocery_intake_screen.dart';
import '../features/health/presentation/health_screen.dart';
import '../features/coach/presentation/coach_screen.dart';
import '../features/meals/data/meal_repository.dart';
import '../features/meals/presentation/add_meal_screen.dart';
import '../features/meals/presentation/meal_detail_screen.dart';
import '../features/meals/presentation/meals_screen.dart';
import '../features/today/presentation/empty_feature_screen.dart';
import '../features/today/presentation/today_screen.dart';
import '../features/notifications/presentation/notification_screen.dart';
import 'shell.dart';
import 'splash_screen.dart';
import '../features/auth/presentation/auth_screen.dart';
import '../features/auth/presentation/email_verification_screen.dart';

final routerProvider = Provider.family<GoRouter, FirebaseConfiguration>((
  ref,
  config,
) {
  final auth = ref.watch(authStateProvider);
  final user = auth.value;
  final userDocument = user == null
      ? null
      : ref.watch(userDocumentProvider(user.uid));

  final router = GoRouter(
    initialLocation: '/splash',
    observers: [
      FirebaseAnalyticsObserver(analytics: FirebaseAnalytics.instance),
    ],
    redirect: (context, state) {
      final path = state.uri.path;
      if (auth.isLoading || auth.hasError) {
        return path == '/splash' ? null : '/splash';
      }
      if (user == null) return path == '/auth' ? null : '/auth';
      if (!user.emailVerified) {
        return path == '/verify-email' ? null : '/verify-email';
      }
      if (userDocument == null ||
          userDocument.isLoading ||
          userDocument.hasError) {
        return path == '/splash' ? null : '/splash';
      }
      final completed = userDocument.value?.onboardingCompleted == true;
      if (!completed && (path == '/auth' || path == '/splash')) {
        return '/onboarding/welcome';
      }
      if (!completed && config.isProduction) {
        return path.startsWith('/onboarding/') ? null : '/onboarding/welcome';
      }
      if (completed &&
          (path == '/auth' ||
              path == '/splash' ||
              path.startsWith('/onboarding/'))) {
        return '/home/today';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SessionSplashScreen(),
      ),
      GoRoute(path: '/auth', builder: (context, state) => const AuthScreen()),
      GoRoute(
        path: '/verify-email',
        builder: (context, state) => const EmailVerificationScreen(),
      ),
      for (final path in [
        '/onboarding/welcome',
        '/onboarding/profile',
        '/onboarding/goals',
        '/onboarding/preferences',
        '/onboarding/routine',
        '/onboarding/kitchen-choice',
        '/onboarding/kitchen-add',
      ])
        GoRoute(
          path: path,
          builder: (context, state) => OnboardingPlaceholder(
            path: path,
            previewEnabled: !config.isProduction,
          ),
        ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/home/today',
            builder: (context, state) => const TodayScreen(),
          ),
          GoRoute(
            path: '/home/health',
            builder: (context, state) => const HealthScreen(),
          ),
          GoRoute(
            path: '/home/kitchen',
            builder: (context, state) => const KitchenScreen(),
          ),
          GoRoute(
            path: '/home/grocery',
            builder: (context, state) => const GroceryScreen(),
          ),
          GoRoute(
            path: '/home/meals',
            builder: (context, state) => const MealsScreen(),
          ),
        ],
      ),
      for (final entry in {'/meals/review': 'Review meal'}.entries)
        GoRoute(
          path: entry.key,
          builder: (context, state) => EmptyFeatureScreen(title: entry.value),
        ),
      GoRoute(path: '/coach', builder: (context, state) => const CoachScreen()),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationScreen(),
      ),
      GoRoute(
        path: '/grocery/shopping',
        builder: (context, state) => const ShoppingScreen(),
      ),
      GoRoute(
        path: '/grocery/intake',
        builder: (context, state) => const GroceryIntakeScreen(),
      ),
      GoRoute(
        path: '/meals/add',
        builder: (context, state) => const AddMealScreen(),
      ),
      GoRoute(
        path: '/kitchen/add',
        builder: (context, state) => const InventoryItemScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) =>
            SettingsScreen(environment: config.environment),
      ),
      GoRoute(
        path: '/meals/:mealId',
        builder: (context, state) =>
            MealDetailScreen(meal: state.extra as MealLog?),
      ),
      GoRoute(
        path: '/kitchen/:inventoryId',
        builder: (context, state) =>
            InventoryItemScreen(item: state.extra as InventoryItem?),
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});
