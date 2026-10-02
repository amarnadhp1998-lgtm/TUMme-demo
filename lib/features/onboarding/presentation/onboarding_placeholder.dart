import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/analytics/feature_analytics.dart';
import '../../../core/auth/auth_repository.dart';
import '../../../core/firebase/messaging_service.dart';
import '../../../shared/design_system/app_strings.dart';
import '../data/onboarding_repository.dart';

class OnboardingPlaceholder extends ConsumerStatefulWidget {
  const OnboardingPlaceholder({
    required this.path,
    required this.previewEnabled,
    super.key,
  });
  final String path;
  final bool previewEnabled;
  @override
  ConsumerState<OnboardingPlaceholder> createState() => _OnboardingState();
}

class _OnboardingState extends ConsumerState<OnboardingPlaceholder> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final dob = TextEditingController(text: '1990-01-01');
  final height = TextEditingController(text: '170');
  final weight = TextEditingController(text: '70');
  final energy = TextEditingController(text: '2000');
  final protein = TextEditingController(text: '80');
  final fiber = TextEditingController(text: '30');
  final water = TextEditingController(text: '2500');
  final cuisines = TextEditingController();
  final dislikes = TextEditingController();
  final avoidFoods = TextEditingController();
  final allergies = TextEditingController();
  final wake = TextEditingController(text: '07:00');
  final sleep = TextEditingController(text: '23:00');
  final breakfast = TextEditingController(text: '09:00');
  final lunch = TextEditingController(text: '14:00');
  final dinner = TextEditingController(text: '20:00');
  String country = 'IN', timezone = 'Asia/Kolkata', sex = 'unspecified';
  String activity = 'moderate', goal = 'eat_healthier', diet = 'omnivore';
  String groceryDay = 'Saturday';
  bool hydrationReminders = false, busy = false;

  static const paths = [
    '/onboarding/welcome',
    '/onboarding/profile',
    '/onboarding/goals',
    '/onboarding/preferences',
    '/onboarding/routine',
    '/onboarding/kitchen-choice',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.path == paths.first) {
      unawaited(
        ref
            .read(featureAnalyticsProvider)
            .record(FeatureEvent.onboardingStarted),
      );
    }
  }

  @override
  void dispose() {
    for (final value in [
      name,
      dob,
      height,
      weight,
      energy,
      protein,
      fiber,
      water,
      cuisines,
      dislikes,
      avoidFoods,
      allergies,
      wake,
      sleep,
      breakfast,
      lunch,
      dinner,
    ]) {
      value.dispose();
    }
    super.dispose();
  }

  List<String> list(String value) =>
      value.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Future<void> next() async {
    if (formKey.currentState?.validate() == false) return;
    final repository = ref.read(onboardingRepositoryProvider);
    setState(() => busy = true);
    try {
      if (widget.path == paths[1]) {
        await repository.saveProfile(
          displayName: name.text,
          country: country,
          timezone: timezone,
          dateOfBirth: dob.text,
          sex: sex,
          heightCm: double.parse(height.text),
          weightKg: double.parse(weight.text),
          activityLevel: activity,
        );
      } else if (widget.path == paths[2]) {
        await repository.savePrivate('goals', {
          'primaryGoal': goal,
          'energyKcal': double.parse(energy.text),
          'proteinG': double.parse(protein.text),
          'fiberG': double.parse(fiber.text),
          'waterMl': double.parse(water.text),
          'source': 'user',
        });
      } else if (widget.path == paths[3]) {
        await repository.savePrivate('preferences', {
          'dietType': diet,
          'preferredCuisines': list(cuisines.text),
          'dislikes': list(dislikes.text),
          'avoidFoods': list(avoidFoods.text),
          'allergies': list(allergies.text),
        });
      } else if (widget.path == paths[4]) {
        if (hydrationReminders) {
          final allowed = await ref
              .read(messagingServiceProvider)
              .enableForReminders();
          if (!allowed) hydrationReminders = false;
        }
        await repository.savePrivate('routine', {
          'wakeTime': wake.text,
          'sleepTime': sleep.text,
          'breakfastTime': breakfast.text,
          'lunchTime': lunch.text,
          'dinnerTime': dinner.text,
          'preferredGroceryDay': groceryDay,
          'hydrationRemindersEnabled': hydrationReminders,
          'expiryAlertsEnabled': true,
          'lowStockAlertsEnabled': true,
          'mealRemindersEnabled': false,
          'weeklySummaryEnabled': true,
        });
      }
      final index = paths.indexOf(widget.path);
      if (mounted && index < paths.length - 1) context.go(paths[index + 1]);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save this step. Try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> finish(bool kitchen) async {
    setState(() => busy = true);
    try {
      await ref.read(onboardingRepositoryProvider).finish();
      await ref
          .read(featureAnalyticsProvider)
          .record(FeatureEvent.onboardingCompleted);
      if (mounted) context.go(kitchen ? '/kitchen/add' : '/home/today');
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not finish setup.')),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final index = paths.indexOf(widget.path).clamp(0, paths.length - 1);
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.appName),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: Semantics(
            label: 'Onboarding step ${index + 1} of ${paths.length}',
            child: LinearProgressIndicator(value: (index + 1) / paths.length),
          ),
        ),
      ),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            ...content(context),
            if (widget.path != paths.last) ...[
              const SizedBox(height: 24),
              FilledButton(
                onPressed: busy ? null : next,
                child: Text(
                  busy
                      ? 'Saving…'
                      : widget.path == paths.first
                      ? 'Get started'
                      : 'Save and continue',
                ),
              ),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: busy
                  ? null
                  : () => ref.read(authRepositoryProvider).signOut(),
              child: const Text('Sign out'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> content(BuildContext context) {
    if (widget.path == paths.first) {
      return [
        Text(
          AppStrings.welcomeHeadline,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 20),
        for (final item in const [
          ('Understand your intake', Icons.insights_outlined),
          ('Manage your kitchen', Icons.kitchen_outlined),
          ('Get smarter suggestions', Icons.auto_awesome_outlined),
        ])
          Card(
            child: ListTile(leading: Icon(item.$2), title: Text(item.$1)),
          ),
      ];
    }
    if (widget.path == paths[1]) {
      return [
        heading(
          context,
          'About you',
          'Used for personalization and editable later.',
        ),
        text(name, 'Display name', required: true, minLength: 2),
        text(dob, 'Date of birth (YYYY-MM-DD)', required: true),
        dropdown('Reference sex', sex, const {
          'unspecified': 'Prefer not to say',
          'female': 'Female',
          'male': 'Male',
        }, (v) => sex = v),
        number(height, 'Height (cm)', 80, 250),
        number(weight, 'Weight (kg)', 25, 350),
        dropdown('Activity level', activity, const {
          'sedentary': 'Sedentary',
          'light': 'Light',
          'moderate': 'Moderate',
          'high': 'High',
          'very_high': 'Very high',
        }, (v) => activity = v),
        dropdown(
          'Country',
          country,
          const {
            'IN': 'India',
            'DE': 'Germany',
            'US': 'United States',
            'GB': 'United Kingdom',
          },
          (v) {
            country = v;
            timezone = v == 'IN'
                ? 'Asia/Kolkata'
                : v == 'DE'
                ? 'Europe/Berlin'
                : v == 'GB'
                ? 'Europe/London'
                : 'America/New_York';
          },
        ),
      ];
    }
    if (widget.path == paths[2]) {
      return [
        heading(
          context,
          'Your goals',
          'Choose a focus and confirm editable daily targets.',
        ),
        dropdown('Primary goal', goal, const {
          'eat_healthier': 'Eat healthier',
          'increase_protein': 'Increase protein',
          'improve_diversity': 'Improve food diversity',
          'reduce_waste': 'Reduce food waste',
          'hydrate': 'Hydrate',
          'lose_weight': 'Lose weight',
          'gain_weight': 'Gain weight',
          'maintain_weight': 'Maintain weight',
        }, (v) => goal = v),
        number(energy, 'Energy (kcal)', 800, 6000),
        number(protein, 'Protein (g)', 0, 400),
        number(fiber, 'Fiber (g)', 0, 150),
        number(water, 'Water (ml)', 250, 8000),
      ];
    }
    if (widget.path == paths[3]) {
      return [
        heading(
          context,
          'Preferences and safety',
          'Allergies are treated as hard constraints, but TUM.me cannot guarantee allergen safety.',
        ),
        dropdown('Diet type', diet, const {
          'omnivore': 'Omnivore',
          'vegetarian': 'Vegetarian',
          'vegan': 'Vegan',
          'pescatarian': 'Pescatarian',
        }, (v) => diet = v),
        text(cuisines, 'Preferred cuisines, comma separated'),
        text(dislikes, 'Dislikes, comma separated'),
        text(avoidFoods, 'Foods to avoid, comma separated'),
        text(allergies, 'Allergies, comma separated'),
      ];
    }
    if (widget.path == paths[4]) {
      return [
        heading(
          context,
          'Your routine',
          'Optional timing helps reminders stay relevant.',
        ),
        time(wake, 'Typical wake time'),
        time(sleep, 'Typical sleep time'),
        time(breakfast, 'Breakfast reminder'),
        time(lunch, 'Lunch reminder'),
        time(dinner, 'Dinner reminder'),
        dropdown('Preferred grocery day', groceryDay, const {
          'Monday': 'Monday',
          'Tuesday': 'Tuesday',
          'Wednesday': 'Wednesday',
          'Thursday': 'Thursday',
          'Friday': 'Friday',
          'Saturday': 'Saturday',
          'Sunday': 'Sunday',
        }, (v) => groceryDay = v),
        SwitchListTile(
          value: hydrationReminders,
          onChanged: (v) => setState(() => hydrationReminders = v),
          title: const Text('Hydration reminders'),
          subtitle: const Text('Off until you choose to enable them.'),
        ),
      ];
    }
    return [
      heading(
        context,
        'Set up your kitchen?',
        'Track fridge, freezer, and pantry items to reduce waste and improve suggestions.',
      ),
      FilledButton.icon(
        onPressed: busy ? null : () => finish(true),
        icon: const Icon(Icons.kitchen_outlined),
        label: const Text('Set up my kitchen'),
      ),
      const SizedBox(height: 8),
      OutlinedButton(
        onPressed: busy ? null : () => finish(false),
        child: const Text('Do it later'),
      ),
    ];
  }

  Widget heading(BuildContext context, String title, String subtitle) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(subtitle),
          ],
        ),
      );
  Widget text(
    TextEditingController c,
    String label, {
    bool required = false,
    int minLength = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: c,
      decoration: InputDecoration(labelText: label),
      validator: required
          ? (v) => v == null || v.trim().length < minLength ? 'Required' : null
          : null,
    ),
  );
  Widget time(TextEditingController controller, String label) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: controller,
      keyboardType: TextInputType.datetime,
      decoration: InputDecoration(labelText: '$label (HH:mm)'),
      validator: (value) =>
          RegExp(r'^([01]\d|2[0-3]):[0-5]\d$').hasMatch(value?.trim() ?? '')
          ? null
          : 'Use 24-hour HH:mm, for example 09:30',
    ),
  );

  Widget number(
    TextEditingController c,
    String label,
    double min,
    double max,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      validator: (v) {
        final n = double.tryParse(v ?? '');
        return n == null || n < min || n > max ? 'Enter $min–$max' : null;
      },
    ),
  );
  Widget dropdown(
    String label,
    String value,
    Map<String, String> options,
    ValueChanged<String> changed,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: options.entries
          .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
          .toList(),
      onChanged: busy ? null : (v) => setState(() => changed(v!)),
    ),
  );
}
