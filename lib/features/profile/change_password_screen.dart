import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/errors.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/core_providers.dart';
import '../../widgets/common.dart';

/// Sets a new password. Opened from Settings, or automatically after the
/// user follows a password-reset link.
class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key, this.fromReset = false});
  final bool fromReset;

  @override
  ConsumerState<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(userRepositoryProvider).updatePassword(_password.text, _confirm.text);
      if (!mounted) return;
      showSnack(context, 'Password updated');
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/jobs');
      }
    } catch (e) {
      setState(() => _error = AppException.describe(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.fromReset ? 'Choose a new password' : 'Change password')),
        body: ResponsiveCenter(
          maxWidth: 480,
          child: ListView(padding: const EdgeInsets.all(AppSpacing.gutter), children: [
            Text(
              widget.fromReset
                  ? 'You\'re signed in from your reset link. Choose a new password to finish.'
                  : 'Use at least 8 characters.',
              style: context.text.bodyLarge?.copyWith(color: context.palette.muted),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _password,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'New password',
                suffixIcon: IconButton(
                  tooltip: _obscure ? 'Show password' : 'Hide password',
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _confirm,
              obscureText: _obscure,
              autofillHints: const [AutofillHints.newPassword],
              onSubmitted: (_) => _save(),
              decoration: const InputDecoration(labelText: 'Confirm new password'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 14),
              Semantics(
                liveRegion: true,
                child: Text(_error!, style: context.text.bodyMedium?.copyWith(color: AppColors.danger)),
              ),
            ],
            const SizedBox(height: 24),
            PrimaryButton(label: 'Save password', loading: _busy, onPressed: _save),
          ]),
        ),
      );
}
