import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/models.dart';
import '../../../providers/core_providers.dart';
import '../../../providers/referral_providers.dart';
import '../../../providers/session_providers.dart';
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

  late final String? _pendingReferral = PendingReferral.read(ref.read(localStoreProvider));

  Future<void> _submit() async {
    final form = _form.currentState;
    final draft = form?.result();
    if (form == null || draft == null) return;
    final logo = form.pickedLogo;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      // Logo and referral are saved before the dashboard opens.
      final result = await ref.read(companyProvider.notifier).register(
            draft,
            logoBytes: logo?.bytes,
            logoName: logo?.name ?? 'logo.jpg',
            referralCode: form.referralCode,
          );
      final problems = [
        if (result.logoError != null) 'the logo didn\'t upload (${result.logoError}). Add it from Company profile',
        if (result.referralError != null) 'the referral code wasn\'t applied (${result.referralError})',
      ];
      messenger.showSnackBar(SnackBar(
        content: Text(problems.isEmpty ? 'Welcome to Vocation SL! Your company profile is ready.' : 'Company created, but ${problems.join('; ')}.'),
        duration: Duration(seconds: problems.isEmpty ? 4 : 8),
      ));
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
            CompanyForm(key: _form, askReferral: true, initialReferral: _pendingReferral),
            const SizedBox(height: 24),
            PrimaryButton(label: 'Create company profile', loading: _saving, onPressed: _submit),
            if (_saving) ...[
              const SizedBox(height: 10),
              Text('Creating your company and uploading your logo…',
                  textAlign: TextAlign.center, style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
            ],
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
        ConstrainedBox(constraints: const BoxConstraints(maxWidth: 760), child: const TeamSection()),
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

/// Launch offer progress: free postings left and until when. Hidden once used up or over.
class LaunchOfferBanner extends ConsumerWidget {
  const LaunchOfferBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offer = ref.watch(launchOfferProvider).value;
    if (offer == null || !offer.available) return const SizedBox.shrink();
    final until = offer.until == null ? '' : ' until ${Fmt.date(offer.until!)}';
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.colors.primaryContainer,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
      ),
      child: Row(children: [
        Icon(Icons.celebration_rounded, color: context.colors.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Launch offer: ${offer.remaining} of ${offer.freePosts} free job postings left',
                style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('Post your first ${offer.freePosts} jobs free$until. No invoice to pay for these.', style: context.text.bodyMedium),
          ]),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 56,
          height: 56,
          child: Stack(alignment: Alignment.center, children: [
            CircularProgressIndicator(value: offer.freePosts == 0 ? 0 : offer.remaining / offer.freePosts, strokeWidth: 5),
            Text('${offer.remaining}', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          ]),
        ),
      ]),
    );
  }
}

/// The company owner adds colleagues (by the email they signed up with) to
/// share jobs and candidates. Recruiters see the list but can't change it.
class TeamSection extends ConsumerStatefulWidget {
  const TeamSection({super.key});

  @override
  ConsumerState<TeamSection> createState() => _TeamSectionState();
}

class _TeamSectionState extends ConsumerState<TeamSection> {
  final _email = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final email = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      showSnack(context, 'Enter your colleague\'s email address.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(employerBackendProvider).addTeamMember(email);
      _email.clear();
      ref.invalidate(teamProvider);
      if (mounted) showSnack(context, '$email can now manage your jobs and candidates.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(TeamMember m) async {
    final ok = await confirmDialog(context,
        title: 'Remove ${m.name.isEmpty ? m.email : m.name}?',
        message: 'They will no longer see your jobs or candidates.',
        confirmLabel: 'Remove',
        destructive: true);
    if (!ok) return;
    try {
      await ref.read(employerBackendProvider).removeTeamMember(m.userId);
      ref.invalidate(teamProvider);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final team = ref.watch(teamProvider);
    final me = ref.watch(sessionProvider);
    final members = team.value ?? const <TeamMember>[];
    final iAmOwner = members.any((m) => m.isOwner && m.userId == me) || (members.length == 1 && members.first.isOwner);
    return SectionCard(
      title: 'Team',
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Colleagues on your team can post jobs, review candidates and message applicants.',
            style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
        const SizedBox(height: 8),
        if (team.isLoading && !team.hasValue) const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator())),
        if (team.hasError) Text('Team couldn\'t be loaded.', style: context.text.bodySmall),
        for (final m in members)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: UserAvatar(initials: (m.name.isNotEmpty ? m.name : m.email).substring(0, 1).toUpperCase(), size: 36),
            title: Text(m.name.isEmpty ? m.email : m.name),
            subtitle: Text('${m.email} · ${m.isOwner ? 'Owner' : 'Recruiter'}'),
            trailing: iAmOwner && !m.isOwner
                ? IconButton(tooltip: 'Remove', icon: const Icon(Icons.person_remove_outlined), onPressed: () => _remove(m))
                : null,
          ),
        if (iAmOwner) ...[
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Colleague\'s email', hintText: 'They must have a Vocation SL account', isDense: true),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 10),
            FilledButton.icon(
              onPressed: _busy ? null : _add,
              icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
              label: const Text('Add'),
            ),
          ]),
        ],
      ]),
    );
  }
}