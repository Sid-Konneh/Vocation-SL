import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../admin/admin_providers.dart';
import '../../core/theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/vocation_logo.dart';
import '../profile/sign_out.dart';

/// Shown instead of the app when an admin has suspended the account.
class SuspendedScreen extends ConsumerWidget {
  const SuspendedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(platformSettingsProvider).value?.supportEmail ?? 'vocationxsl@gmail.com';
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const VocationMark(size: 48),
                const SizedBox(height: 24),
                Text('Your account is suspended', style: context.text.headlineMedium),
                const SizedBox(height: 12),
                Text(
                  'You can\'t apply for jobs, post jobs or register a company while your account is suspended. '
                  'If you think this is a mistake, contact our team and we\'ll review it.',
                  style: context.text.bodyLarge?.copyWith(color: context.palette.muted),
                ),
                const SizedBox(height: 20),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.mail_outline_rounded),
                    title: SelectableText(email),
                    subtitle: const Text('Support'),
                    trailing: IconButton(
                      tooltip: 'Copy email address',
                      icon: const Icon(Icons.copy_rounded),
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: email));
                        if (context.mounted) showSnack(context, 'Email address copied');
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: () => confirmAndSignOut(context, ref),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
