import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/session_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';
import 'notifications_screen.dart';

const _descriptions = {
  NotificationType.newMatch: 'Jobs that match your profile and preferences',
  NotificationType.savedSearch: 'New results for your saved searches',
  NotificationType.submitted: 'Confirmation when an application is sent',
  NotificationType.viewed: 'When an employer opens your application',
  NotificationType.shortlisted: 'When you make an employer\'s shortlist',
  NotificationType.interview: 'Interview invitations and changes',
  NotificationType.statusChange: 'Other application status updates',
  NotificationType.message: 'Messages from employers',
  NotificationType.deadline: 'Reminders before saved jobs close',
};

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Notification settings')),
      body: async.when(
        loading: () => const SingleChildScrollView(child: NotificationListSkeleton()),
        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(profileProvider)),
        data: (loaded) {
          final user = loaded.data;
          final prefs = user.notificationPreferences;
          Future<void> save(NotificationPreferences p) async {
            final synced = await ref.read(profileProvider.notifier).save(user.copyWith(notificationPreferences: p));
            if (!synced && context.mounted) showSnack(context, 'Saved on this device. Will sync when you\'re online.');
          }

          return ResponsiveCenter(
            maxWidth: AppSpacing.maxReadingWidth,
            child: ListView(padding: const EdgeInsets.symmetric(vertical: 8), children: [
              SwitchListTile(
                title: const Text('Push notifications'),
                subtitle: const Text('Alerts on this device'),
                value: prefs.pushEnabled,
                onChanged: (v) => save(prefs.copyWith(pushEnabled: v)),
              ),
              SwitchListTile(
                title: const Text('Weekly email summary'),
                subtitle: Text('Sent to ${user.email}'),
                value: prefs.emailDigest,
                onChanged: (v) => save(prefs.copyWith(emailDigest: v)),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text('Notify me about', style: context.text.titleMedium),
              ),
              for (final t in NotificationType.values)
                SwitchListTile(
                  secondary: Icon(notificationIcon(t), color: notificationColor(t)),
                  title: Text(t.label),
                  subtitle: Text(_descriptions[t]!),
                  value: prefs.allows(t),
                  onChanged: (v) => save(prefs.toggle(t, v)),
                ),
            ]),
          );
        },
      ),
    );
  }
}
