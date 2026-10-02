import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_repository.dart';
import '../../../core/config/app_capabilities.dart';
import '../../../core/firebase/firebase_config.dart';
import '../../../core/firebase/messaging_service.dart';
import '../../../core/widgets/async_status.dart';
import '../../../core/widgets/demo_unavailable.dart';
import '../data/privacy_repository.dart';
import '../data/profile_settings_repository.dart';
import '../data/reminder_repository.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({required this.environment, super.key});
  final AppEnvironment environment;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool signingOut = false;
  bool failed = false;
  bool privacyBusy = false;
  bool testNotificationBusy = false;

  Future<void> sendTestNotification() async {
    setState(() => testNotificationBusy = true);
    try {
      await ref.read(messagingServiceProvider).sendTestNotification();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Test notification sent.')),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not send a test notification. Check permission and deployment.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => testNotificationBusy = false);
    }
  }

  Future<void> signOut() async {
    setState(() {
      signingOut = true;
      failed = false;
    });
    try {
      await ref.read(authRepositoryProvider).signOut();
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => signingOut = false);
    }
  }

  Future<void> exportData() async {
    setState(() => privacyBusy = true);
    try {
      final json = await ref.read(privacyRepositoryProvider).exportMyData();
      await Clipboard.setData(ClipboardData(text: json));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Your data export was copied to the clipboard.'),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not export your data.')),
        );
      }
    } finally {
      if (mounted) setState(() => privacyBusy = false);
    }
  }

  Future<void> deleteAccount() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete account and data?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'This permanently removes your profile, meals, kitchen, grocery, hydration, and sign-in account.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Type DELETE to confirm',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, controller.text == 'DELETE'),
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (confirmed != true || !mounted) return;
    setState(() => privacyBusy = true);
    try {
      await ref.read(privacyRepositoryProvider).deleteMyAccount();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Deletion failed. Sign out, sign in again, and retry.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => privacyBusy = false);
    }
  }

  Future<void> setReminder(ReminderType type, bool enabled) async {
    try {
      if (enabled) {
        final allowed = await ref
            .read(messagingServiceProvider)
            .enableForReminders();
        if (!allowed) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Allow notifications in device settings to enable reminders.',
                ),
              ),
            );
          }
          return;
        }
      }
      await ref.read(reminderRepositoryProvider).setEnabled(type, enabled);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update reminder settings.')),
        );
      }
    }
  }

  Future<void> editReminderSchedule(ReminderPreferences current) async {
    final controllers = [
      TextEditingController(text: current.wakeTime),
      TextEditingController(text: current.sleepTime),
      TextEditingController(text: current.breakfastTime),
      TextEditingController(text: current.lunchTime),
      TextEditingController(text: current.dinnerTime),
    ];
    final labels = ['Wake time', 'Sleep time', 'Breakfast', 'Lunch', 'Dinner'];
    final formKey = GlobalKey<FormState>();
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reminder schedule'),
        content: Form(
          key: formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < controllers.length; index++)
                  TextFormField(
                    controller: controllers[index],
                    keyboardType: TextInputType.datetime,
                    decoration: InputDecoration(
                      labelText: '${labels[index]} (HH:mm)',
                    ),
                    validator: (value) =>
                        RegExp(
                          r'^([01]\d|2[0-3]):[0-5]\d$',
                        ).hasMatch(value?.trim() ?? '')
                        ? null
                        : 'Use 24-hour HH:mm',
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate())
                Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (save == true) {
      try {
        await ref
            .read(reminderRepositoryProvider)
            .updateSchedule(
              wakeTime: controllers[0].text.trim(),
              sleepTime: controllers[1].text.trim(),
              breakfastTime: controllers[2].text.trim(),
              lunchTime: controllers[3].text.trim(),
              dinnerTime: controllers[4].text.trim(),
            );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not update reminder schedule.'),
            ),
          );
        }
      }
    }
    for (final controller in controllers) controller.dispose();
  }

  Future<void> editAccount(AccountSettings current) async {
    final name = TextEditingController(text: current.displayName);
    final country = TextEditingController(text: current.country);
    final timezone = TextEditingController(text: current.timezone);
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit profile'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Display name'),
              ),
              TextField(
                controller: country,
                textCapitalization: TextCapitalization.characters,
                maxLength: 2,
                decoration: const InputDecoration(
                  labelText: 'Country code',
                  hintText: 'IN',
                ),
              ),
              TextField(
                controller: timezone,
                decoration: const InputDecoration(
                  labelText: 'Timezone',
                  hintText: 'Asia/Kolkata',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (save == true &&
        name.text.trim().length >= 2 &&
        country.text.trim().length == 2 &&
        timezone.text.trim().isNotEmpty) {
      try {
        await ref
            .read(profileSettingsRepositoryProvider)
            .saveAccount(
              displayName: name.text,
              country: country.text,
              timezone: timezone.text,
            );
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not update profile.')),
          );
        }
      }
    }
    name.dispose();
    country.dispose();
    timezone.dispose();
  }

  Future<void> editGoals(GoalSettings current) async {
    final energy = TextEditingController(
      text: current.energyKcal.toStringAsFixed(0),
    );
    final protein = TextEditingController(
      text: current.proteinG.toStringAsFixed(0),
    );
    final fiber = TextEditingController(
      text: current.fiberG.toStringAsFixed(0),
    );
    final water = TextEditingController(
      text: current.waterMl.toStringAsFixed(0),
    );
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit nutrition goals'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final field in [
                (energy, 'Energy (kcal)'),
                (protein, 'Protein (g)'),
                (fiber, 'Fiber (g)'),
                (water, 'Water (ml)'),
              ])
                TextField(
                  controller: field.$1,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: field.$2),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (save == true) {
      final value = GoalSettings(
        energyKcal: double.tryParse(energy.text) ?? -1,
        proteinG: double.tryParse(protein.text) ?? -1,
        fiberG: double.tryParse(fiber.text) ?? -1,
        waterMl: double.tryParse(water.text) ?? -1,
      );
      final valid =
          value.energyKcal >= 800 &&
          value.energyKcal <= 6000 &&
          value.proteinG >= 0 &&
          value.proteinG <= 400 &&
          value.fiberG >= 0 &&
          value.fiberG <= 150 &&
          value.waterMl >= 250 &&
          value.waterMl <= 8000;
      if (valid) {
        try {
          await ref.read(profileSettingsRepositoryProvider).saveGoals(value);
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not update nutrition goals.'),
              ),
            );
          }
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter goals within the supported ranges.'),
          ),
        );
      }
    }
    for (final controller in [energy, protein, fiber, water]) {
      controller.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Environment: ${widget.environment.name}'),
        const SizedBox(height: 24),
        Text('Profile', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ref
            .watch(accountSettingsProvider)
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => ErrorState(
                message: 'Could not load profile settings.',
                onRetry: () => ref.invalidate(accountSettingsProvider),
              ),
              data: (value) => Card(
                child: ListTile(
                  leading: const Icon(Icons.person_outline),
                  title: Text(value.displayName),
                  subtitle: Text(
                    '${value.country} · ${value.timezone} · ${value.unitSystem}',
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => editAccount(value),
                ),
              ),
            ),
        const SizedBox(height: 16),
        Text('Nutrition goals', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        ref
            .watch(goalSettingsProvider)
            .when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => ErrorState(
                message: 'Could not load nutrition goals.',
                onRetry: () => ref.invalidate(goalSettingsProvider),
              ),
              data: (value) => Card(
                child: ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: Text(
                    '${value.energyKcal.toStringAsFixed(0)} kcal · '
                    '${value.proteinG.toStringAsFixed(0)} g protein',
                  ),
                  subtitle: Text(
                    '${value.fiberG.toStringAsFixed(0)} g fiber · '
                    '${value.waterMl.toStringAsFixed(0)} ml water',
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => editGoals(value),
                ),
              ),
            ),
        const SizedBox(height: 16),
        Text('AI preferences', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (!AppCapabilities.cloudAi)
          const DemoUnavailableCard(
            title: 'Cloud AI unavailable in free demo',
            message:
                'Ask TUM still offers simple on-device summaries from your saved data.',
            icon: Icons.info_outline,
          )
        else
          ref
              .watch(aiPersonalizationProvider)
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => ErrorState(
                  message: 'Could not load AI preferences.',
                  onRetry: () => ref.invalidate(aiPersonalizationProvider),
                ),
                data: (enabled) => Card(
                  child: SwitchListTile(
                    title: const Text('Personalized AI guidance'),
                    subtitle: const Text(
                      'Allow TUM to use your goals, recent logs, and kitchen context',
                    ),
                    value: enabled,
                    onChanged: (value) async {
                      try {
                        await ref
                            .read(profileSettingsRepositoryProvider)
                            .setAiPersonalization(value);
                      } catch (_) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Could not update AI preference.'),
                            ),
                          );
                        }
                      }
                    },
                  ),
                ),
              ),
        const SizedBox(height: 24),
        Text('Reminders', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (!AppCapabilities.notifications)
          const DemoUnavailableCard(
            title: 'Notifications unavailable in free demo',
            message:
                'Scheduled reminders and push notifications require the deployed backend.',
          )
        else ...[
          ref
              .watch(reminderPreferencesProvider)
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => ErrorState(
                  message: 'Could not load reminder settings.',
                  onRetry: () => ref.invalidate(reminderPreferencesProvider),
                ),
                data: (value) => Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.schedule_outlined),
                        title: const Text('Reminder schedule'),
                        subtitle: Text(
                          '${value.wakeTime}–${value.sleepTime} · Meals ${value.breakfastTime}, ${value.lunchTime}, ${value.dinnerTime}',
                        ),
                        trailing: const Icon(Icons.edit_outlined),
                        onTap: () => editReminderSchedule(value),
                      ),
                      const Divider(height: 1),
                      _ReminderSwitch(
                        title: 'Expiry alerts',
                        subtitle: 'Items approaching their expiry window',
                        value: value.expiry,
                        onChanged: (enabled) =>
                            setReminder(ReminderType.expiry, enabled),
                      ),
                      _ReminderSwitch(
                        title: 'Low-stock alerts',
                        subtitle: 'Accepted kitchen thresholds are crossed',
                        value: value.lowStock,
                        onChanged: (enabled) =>
                            setReminder(ReminderType.lowStock, enabled),
                      ),
                      _ReminderSwitch(
                        title: 'Hydration reminders',
                        subtitle: 'Within your saved waking hours',
                        value: value.hydration,
                        onChanged: (enabled) =>
                            setReminder(ReminderType.hydration, enabled),
                      ),
                      _ReminderSwitch(
                        title: 'Meal logging reminders',
                        subtitle: 'Optional routine prompts',
                        value: value.meal,
                        onChanged: (enabled) =>
                            setReminder(ReminderType.meal, enabled),
                      ),
                      _ReminderSwitch(
                        title: 'Weekly summary',
                        subtitle: 'Nutrition and food-diversity recap',
                        value: value.weeklySummary,
                        onChanged: (enabled) =>
                            setReminder(ReminderType.weeklySummary, enabled),
                      ),
                    ],
                  ),
                ),
              ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: testNotificationBusy ? null : sendTestNotification,
            icon: const Icon(Icons.notifications_active_outlined),
            label: Text(
              testNotificationBusy
                  ? 'Sending test notification...'
                  : 'Send test notification',
            ),
          ),
        ],
        const SizedBox(height: 24),
        Text('Data & privacy', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (!AppCapabilities.dataExportAndAccountDeletion)
          const DemoUnavailableCard(
            title: 'Account tools unavailable in free demo',
            message:
                'Full data export and complete account deletion require the deployed backend.',
          )
        else ...[
          OutlinedButton.icon(
            onPressed: privacyBusy ? null : exportData,
            icon: const Icon(Icons.download_outlined),
            label: const Text('Copy my data export'),
          ),
          TextButton.icon(
            onPressed: privacyBusy ? null : deleteAccount,
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Delete my account and data'),
          ),
        ],
        const SizedBox(height: 24),
        if (failed)
          ErrorState(message: 'Could not sign out.', onRetry: signOut),
        FilledButton(
          onPressed: signingOut ? null : signOut,
          child: Text(signingOut ? 'Signing out...' : 'Sign out'),
        ),
      ],
    ),
  );
}

class _ReminderSwitch extends StatelessWidget {
  const _ReminderSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    title: Text(title),
    subtitle: Text(subtitle),
    value: value,
    onChanged: onChanged,
  );
}
