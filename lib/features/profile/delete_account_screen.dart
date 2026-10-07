import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../core/config/app_config.dart';
import '../../core/errors.dart';
import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/core_providers.dart';
import '../../providers/session_providers.dart';
import '../../widgets/common.dart';

/// Permanently deletes the signed-in account after a typed confirmation.
class DeleteAccountScreen extends ConsumerStatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  ConsumerState<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends ConsumerState<DeleteAccountScreen> {
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _confirm.dispose();
    super.dispose();
  }

  bool get _typed => _confirm.text.trim().toUpperCase() == 'DELETE';

  Future<void> _delete() async {
    if (!ref.read(onlineProvider)) {
      setState(() => _error = 'You\'re offline. Connect to the internet to delete your account.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(sessionProvider.notifier).deleteAccount();
      // The router returns to the login screen once the session ends.
      scaffoldMessengerKey.currentState?.showSnackBar(
        const SnackBar(content: Text('Your account and data have been deleted.')),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = AppException.describe(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final employer = ref.watch(roleProvider) == UserRole.employer;
    final items = [
      'Your sign-in (email or Google) and your profile, including your CV and documents',
      'Your job applications, saved jobs, saved searches and alerts',
      if (employer) 'If you are the only person on your company account: the company, its logo, its jobs and the applications to them',
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Delete account')),
      body: ResponsiveCenter(
        maxWidth: 560,
        child: ListView(padding: const EdgeInsets.all(AppSpacing.gutter), children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.danger.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              border: const Border(left: BorderSide(color: AppColors.danger, width: 4)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.danger),
              const SizedBox(width: 12),
              Expanded(
                child: Text('This permanently deletes your Vocation SL account. It can\'t be undone.',
                    style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          Text('What will be deleted', style: context.text.titleMedium),
          const SizedBox(height: 10),
          BulletList(items, icon: Icons.remove_circle_outline_rounded),
          const SizedBox(height: 8),
          Text(
            'Employers you already applied to may keep copies they downloaded. '
            'Questions? Email ${AppConfig.supportEmail}.',
            style: context.text.bodySmall?.copyWith(color: context.palette.muted),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _confirm,
            enabled: !_busy,
            onChanged: (_) => setState(() {}),
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Type DELETE to confirm'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Semantics(liveRegion: true, child: Text(_error!, style: context.text.bodyMedium?.copyWith(color: AppColors.danger))),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _typed && !_busy ? _delete : null,
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger, foregroundColor: Colors.white),
              icon: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.delete_forever_rounded),
              label: const Text('Delete my account permanently'),
            ),
          ),
        ]),
      ),
    );
  }
}
