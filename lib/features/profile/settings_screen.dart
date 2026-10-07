import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/app_theme.dart';
import '../../data/backend/demo_backend.dart';
import '../../providers/core_providers.dart';
import '../../providers/job_providers.dart';
import '../../providers/session_providers.dart';
import '../../providers/user_data_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/vocation_logo.dart';
import '../../models/models.dart';
import '../auth/role_choice_screen.dart';
import 'sign_out.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  void _invalidateAll(WidgetRef ref) {
    ref.invalidate(profileProvider);
    ref.invalidate(applicationsProvider);
    ref.invalidate(notificationsProvider);
    ref.invalidate(savedJobsProvider);
    ref.invalidate(alertsProvider);
    ref.invalidate(homeFeedProvider);
    ref.invalidate(searchProvider);
    ref.invalidate(companiesProvider);
    ref.invalidate(pendingSyncCountProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dev = ref.watch(devSettingsProvider);
    final backend = ref.watch(backendProvider);
    final pending = ref.watch(pendingSyncCountProvider);
    final online = ref.watch(onlineProvider);
    final user = ref.watch(profileProvider).value?.data;

    Widget header(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
          child: Semantics(header: true, child: Text(t, style: context.text.titleMedium)),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ResponsiveCenter(
        maxWidth: AppSpacing.maxReadingWidth,
        child: ListView(children: [
          header('Account'),
          ListTile(leading: const Icon(Icons.mail_outline_rounded), title: const Text('Email'), subtitle: Text(user?.email ?? '')),
          ListTile(
            leading: const Icon(Icons.swap_horiz_rounded),
            title: const Text('Switch to employer'),
            subtitle: const Text('Post jobs and review candidates for your company'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => switchRole(context, ref, UserRole.employer),
          ),
          ListTile(
            leading: const Icon(Icons.lock_outline_rounded),
            title: const Text('Change password'),
            subtitle: const Text('Accounts created with Google can set one here too'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/settings/password'),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: const Text('Choose which alerts you receive'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/settings/notifications'),
          ),
          header('Offline & sync'),
          ListTile(
            leading: Icon(online ? Icons.cloud_done_outlined : Icons.cloud_off_outlined),
            title: Text(online ? 'Online' : 'Offline'),
            subtitle: Text(pending == 0 ? 'All changes are synced' : '$pending change${pending == 1 ? '' : 's'} waiting to sync'),
            trailing: TextButton(
              onPressed: !online
                  ? null
                  : () async {
                      final r = await ref.read(syncServiceProvider).flush();
                      ref.invalidate(pendingSyncCountProvider);
                      if (context.mounted) showSnack(context, r.synced == 0 ? 'Nothing to sync' : 'Synced ${r.synced} changes');
                    },
              child: const Text('Sync now'),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.cleaning_services_outlined),
            title: const Text('Clear cached data'),
            subtitle: const Text('Frees space. Jobs will reload next time you\'re online.'),
            onTap: () async {
              final ok = await confirmDialog(context,
                  title: 'Clear cached data?', message: 'Saved copies of jobs and your data will be removed from this device. Pending changes are kept.', confirmLabel: 'Clear');
              if (!ok) return;
              await ref.read(localStoreProvider).clearCache();
              _invalidateAll(ref);
              if (context.mounted) showSnack(context, 'Cache cleared');
            },
          ),
          header('Testing tools'),
          SwitchListTile(
            secondary: const Icon(Icons.wifi_off_rounded),
            title: const Text('Simulate offline mode'),
            subtitle: const Text('Test offline browsing, queued applications and sync'),
            value: dev.simulateOffline,
            onChanged: (v) => ref.read(devSettingsProvider.notifier).update(dev.copyWith(simulateOffline: v)),
          ),
          if (isDemoBackend(backend)) ...[
            SwitchListTile(
              secondary: const Icon(Icons.network_check_rounded),
              title: const Text('Slow network'),
              subtitle: const Text('Adds 2–3 seconds to every request to show loading states'),
              value: dev.slowNetwork,
              onChanged: (v) => ref.read(devSettingsProvider.notifier).update(dev.copyWith(slowNetwork: v)),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.error_outline_rounded),
              title: const Text('Simulate server errors'),
              subtitle: const Text('About half of requests fail, to test error and retry states'),
              value: dev.failRequests,
              onChanged: (v) => ref.read(devSettingsProvider.notifier).update(dev.copyWith(failRequests: v)),
            ),
            ListTile(
              leading: const Icon(Icons.restart_alt_rounded),
              title: const Text('Reset demo data'),
              subtitle: const Text('Restore the sample applications, saved jobs and alerts'),
              onTap: () async {
                final ok = await confirmDialog(context,
                    title: 'Reset demo data?', message: 'Your changes in demo mode will be lost.', confirmLabel: 'Reset', destructive: true);
                if (!ok) return;
                await (backend as DemoBackend).reset();
                await ref.read(localStoreProvider).clearCache();
                await ref.read(localStoreProvider).clearOutbox();
                _invalidateAll(ref);
                if (context.mounted) showSnack(context, 'Demo data restored');
              },
            ),
          ],
          header('About'),
          ListTile(
            leading: const VocationMark(size: 28),
            title: const Text('About Vocation SL'),
            subtitle: Text('Version ${AppConfig.version}${isDemoBackend(backend) ? ' · demo mode' : ''}'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/about'),
          ),
          ListTile(
            leading: const Icon(Icons.support_agent_outlined),
            title: const Text('Help & support'),
            subtitle: const SelectableText(AppConfig.supportEmail),
            trailing: IconButton(
              tooltip: 'Copy email address',
              icon: const Icon(Icons.copy_rounded),
              onPressed: () async {
                await Clipboard.setData(const ClipboardData(text: AppConfig.supportEmail));
                if (context.mounted) showSnack(context, 'Email address copied');
              },
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: OutlinedButton.icon(
              onPressed: () => confirmAndSignOut(context, ref),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Sign out'),
            ),
          ),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }
}
