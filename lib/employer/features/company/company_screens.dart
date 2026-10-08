import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/models.dart';
import '../../../widgets/common.dart';
import '../../../widgets/vocation_logo.dart';
import '../../../features/profile/sign_out.dart';
import '../../providers.dart';
import '../../widgets.dart';
import 'company_form.dart';

/// First run: register the company. It starts as "awaiting approval".
class CompanySetupScreen extends ConsumerStatefulWidget {
  const CompanySetupScreen({super.key});

  @override
  ConsumerState<CompanySetupScreen> createState() => _CompanySetupScreenState();
}

class _CompanySetupScreenState extends ConsumerState<CompanySetupScreen> {
  final _form = GlobalKey<CompanyFormState>();
  bool _saving = false;

  Future<void> _submit() async {
    final draft = _form.currentState?.result();
    if (draft == null) return;
    final logo = _form.currentState?.pickedLogo;
    final notifier = ref.read(companyProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final company = await notifier.register(draft);
      if (logo != null) {
        try {
          await notifier.uploadLogo(company, logo.bytes, logo.name);
        } catch (e) {
          // The company exists; the logo can be added later from Company profile.
          messenger.showSnackBar(SnackBar(content: Text('Company created, but the logo didn\'t upload: ${AppException.describe(e)}')));
        }
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const VocationLogo(size: 28),
          actions: [TextButton(onPressed: () => confirmAndSignOut(context, ref), child: const Text('Sign out'))],
        ),
        body: ResponsiveCenter(
          maxWidth: 720,
          child: ListView(padding: const EdgeInsets.all(AppSpacing.gutter), children: [
            Text('Set up your company', style: context.text.headlineMedium),
            const SizedBox(height: 8),
            Text(
              'Tell candidates who you are. Our team reviews every new company before its jobs go live. '
              'You can draft and submit jobs in the meantime.',
              style: context.text.bodyLarge?.copyWith(color: context.palette.muted),
            ),
            const SizedBox(height: 24),
            CompanyForm(key: _form),
            const SizedBox(height: 24),
            PrimaryButton(label: 'Create company profile', loading: _saving, onPressed: _submit),
            const SizedBox(height: 40),
          ]),
        ),
      );
}

class CompanyProfileScreen extends ConsumerStatefulWidget {
  const CompanyProfileScreen({super.key});

  @override
  ConsumerState<CompanyProfileScreen> createState() => _CompanyProfileScreenState();
}

class _CompanyProfileScreenState extends ConsumerState<CompanyProfileScreen> {
  final _form = GlobalKey<CompanyFormState>();
  bool _saving = false;

  Future<void> _save() async {
    final updated = _form.currentState?.result();
    if (updated == null) return;
    final logo = _form.currentState?.pickedLogo;
    setState(() => _saving = true);
    try {
      final saved = await ref.read(companyProvider.notifier).save(updated);
      if (logo != null) await ref.read(companyProvider.notifier).uploadLogo(saved, logo.bytes, logo.name);
      if (mounted) showSnack(context, logo != null ? 'Company profile and logo saved' : 'Company profile saved');
    } on NetworkException {
      if (mounted) showSnack(context, 'You\'re offline. Connect to save changes.', error: true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(companyProvider).value?.data;
    if (company == null) return const SizedBox();
    return EmployerPage(
      title: 'Company profile',
      subtitle: 'How your company appears to candidates.',
      actions: [
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save_outlined),
          label: const Text('Save changes'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
        ),
      ],
      children: [
        ApprovalBanner(company: company),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Card(child: Padding(padding: const EdgeInsets.all(20), child: CompanyForm(key: _form, initial: company))),
        ),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => context.push('/account/delete'),
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Delete account'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          ),
        ),
      ],
    );
  }
}

/// Explains the company's approval state. Hidden once approved.
class ApprovalBanner extends StatelessWidget {
  const ApprovalBanner({super.key, required this.company});
  final Company company;

  @override
  Widget build(BuildContext context) {
    if (company.isApproved) return const SizedBox.shrink();
    final (color, icon, title, body) = switch (company.status) {
      CompanyStatus.pending => (
          AppColors.warning,
          Icons.hourglass_top_rounded,
          'Your company is awaiting approval',
          'You can post jobs now. They are saved as "Awaiting approval" and reviewed by our team once your company is approved. '
              'Questions? Email vocationxsl@gmail.com.',
        ),
      CompanyStatus.rejected => (
          AppColors.danger,
          Icons.error_outline_rounded,
          'Your company was not approved',
          'Please email vocationxsl@gmail.com so we can help you complete verification.',
        ),
      _ => (
          AppColors.danger,
          Icons.block_rounded,
          'Your company account is suspended',
          'Your jobs are hidden from candidates. Email vocationxsl@gmail.com for details.',
        ),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(body, style: context.text.bodyMedium),
          ]),
        ),
      ]),
    );
  }
}
