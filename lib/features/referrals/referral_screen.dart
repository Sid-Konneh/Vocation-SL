import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/core_providers.dart';
import '../../providers/referral_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/states.dart';

/// Job seekers refer employers. A referral counts the company signing up and
/// every job it posts that goes live.
class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key});

  Future<void> _share(BuildContext context, WidgetRef ref, String code) async {
    final copied = await ref.read(shareServiceProvider).shareText(ref.read(shareServiceProvider).referralText(code), subject: 'Post your jobs on Vocation SL');
    if (copied && context.mounted) showSnack(context, 'Invitation copied. Paste it into WhatsApp, SMS or email.');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = ref.watch(myReferralCodeProvider);
    final referrals = ref.watch(myReferralsProvider);
    final reward = ref.watch(referralRewardProvider).value ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Refer an employer')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myReferralsProvider);
          ref.invalidate(referralRewardProvider);
          await ref.read(myReferralsProvider.future);
        },
        child: ResponsiveCenter(
          maxWidth: AppSpacing.maxReadingWidth,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, AppSpacing.gutter, 40),
            children: [
              Text('Know a company that\'s hiring?', style: context.text.headlineSmall),
              const SizedBox(height: 6),
              Text(
                'Share your link with businesses, NGOs, schools or anyone who hires. When they create their company with your code, '
                'the company and every job it posts on Vocation SL count as your referral.',
                style: context.text.bodyLarge?.copyWith(color: context.palette.muted),
              ),
              if (reward.isNotEmpty) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.colors.primaryContainer,
                    borderRadius: BorderRadius.circular(AppSpacing.radius),
                  ),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.card_giftcard_rounded, color: context.colors.primary),
                    const SizedBox(width: 12),
                    Expanded(child: Text(reward, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                  ]),
                ),
              ],
              const SizedBox(height: 20),
              code.when(
                loading: () => const Card(child: SizedBox(height: 140, child: Center(child: CircularProgressIndicator()))),
                error: (e, _) => ErrorState(error: e, compact: true, onRetry: () => ref.invalidate(myReferralCodeProvider)),
                data: (c) => _CodeCard(code: c, onShare: () => _share(context, ref, c)),
              ),
              const SizedBox(height: 16),
              const _PayoutCard(),
              const SizedBox(height: 20),
              referrals.when(
                loading: () => const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                error: (e, _) => ErrorState(error: e, compact: true, onRetry: () => ref.invalidate(myReferralsProvider)),
                data: (list) => _ReferralList(referrals: list),
              ),
              const SizedBox(height: 24),
              const _HowItWorks(),
            ],
          ),
        ),
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code, required this.onShare});
  final String code;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final link = ReferralCode.link(code);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Your referral code', style: context.text.labelLarge?.copyWith(color: context.palette.muted)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: SelectableText(ReferralCode.display(code),
                  style: context.text.headlineMedium?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 1.5, color: context.colors.primary)),
            ),
            IconButton(
              tooltip: 'Copy code',
              icon: const Icon(Icons.copy_rounded),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: ReferralCode.display(code)));
                if (context.mounted) showSnack(context, 'Code copied');
              },
            ),
          ]),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: Text(link, style: context.text.bodySmall?.copyWith(color: context.palette.muted), overflow: TextOverflow.ellipsis)),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: link));
                if (context.mounted) showSnack(context, 'Link copied');
              },
              child: const Text('Copy link'),
            ),
          ]),
          const SizedBox(height: 10),
          PrimaryButton(label: 'Share with an employer', icon: Icons.share_rounded, onPressed: onShare),
        ]),
      ),
    );
  }
}

class _ReferralList extends StatelessWidget {
  const _ReferralList({required this.referrals});
  final List<Referral> referrals;

  @override
  Widget build(BuildContext context) {
    final s = ReferralSummary(referrals);
    Widget stat(String value, String label) => Expanded(
          child: Column(children: [
            Text(value, style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, textAlign: TextAlign.center, style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Row(children: [
            stat('${s.total}', 'Companies referred'),
            stat('${s.jobsPosted}', 'Jobs posted'),
            stat('${s.rewarded}', 'Rewarded'),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      Text('Your referrals', style: context.text.titleMedium),
      const SizedBox(height: 8),
      if (referrals.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('No referrals yet. Share your code with a company that\'s hiring; it shows up here when they sign up.',
              style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
        )
      else
        for (final r in referrals) _ReferralTile(referral: r),
    ]);
  }
}

class _ReferralTile extends StatelessWidget {
  const _ReferralTile({required this.referral});
  final Referral referral;

  @override
  Widget build(BuildContext context) {
    final r = referral;
    final color = switch (r.status) {
      ReferralStatus.signedUp => AppColors.warning,
      ReferralStatus.approved => AppColors.info,
      ReferralStatus.qualified => AppColors.green,
      ReferralStatus.rewarded => AppColors.purple,
      ReferralStatus.rejected => AppColors.danger,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(r.companyName.isEmpty ? 'New company' : r.companyName, style: context.text.titleSmall)),
            TagChip(r.status.label, color: color, background: color.withValues(alpha: 0.12), dense: true),
          ]),
          const SizedBox(height: 4),
          Text('Joined ${Fmt.dateShort(r.createdAt)} · ${r.jobsPosted} job${r.jobsPosted == 1 ? '' : 's'} posted',
              style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
          if (r.status != ReferralStatus.rejected) ...[
            const SizedBox(height: 10),
            _Steps(status: r.status),
          ],
          if (r.jobs.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final j in r.jobs.reversed.take(5))
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(children: [
                  Icon(Icons.work_outline_rounded, size: 16, color: context.palette.muted),
                  const SizedBox(width: 6),
                  Expanded(child: Text(j.title, style: context.text.bodySmall, overflow: TextOverflow.ellipsis)),
                  Text(Fmt.dateShort(j.publishedAt), style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
                ]),
              ),
            if (r.jobs.length > 5)
              Text('and ${r.jobs.length - 5} more', style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
          ],
          if (r.note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(r.note, style: context.text.bodySmall),
          ],
        ]),
      ),
    );
  }
}

class _Steps extends StatelessWidget {
  const _Steps({required this.status});
  final ReferralStatus status;

  @override
  Widget build(BuildContext context) {
    final reached = ReferralStatus.steps.indexOf(status);
    return Row(children: [
      for (var i = 0; i < ReferralStatus.steps.length; i++) ...[
        Expanded(
          child: Column(children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: i <= reached ? context.colors.primary : context.palette.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 4),
            Text(ReferralStatus.steps[i].label,
                textAlign: TextAlign.center,
                style: context.text.labelSmall?.copyWith(color: i <= reached ? context.colors.onSurface : context.palette.muted)),
          ]),
        ),
        if (i < ReferralStatus.steps.length - 1) const SizedBox(width: 4),
      ],
    ]);
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.share_rounded, 'Share your link or code', 'Send it to a company that hires, by WhatsApp, SMS or email.'),
      (Icons.business_rounded, 'They create their company', 'They open your link, or enter your code when they sign up as an employer.'),
      (Icons.verified_rounded, 'We review the company', 'Our team checks every new company before its jobs go live.'),
      (Icons.work_rounded, 'Their jobs count for you', 'Every job they post that goes live is added to your referral.'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('How it works', style: context.text.titleMedium),
      const SizedBox(height: 10),
      for (final (icon, title, body) in steps)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(radius: 18, backgroundColor: context.colors.primaryContainer, child: Icon(icon, size: 18, color: context.colors.primary)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: context.text.titleSmall),
                Text(body, style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
              ]),
            ),
          ]),
        ),
      Text('A company can only be referred once, and you can\'t refer your own company.',
          style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
    ]);
  }
}

/// Where rewards are paid: the referrer's own Mobile Money account.
class _PayoutCard extends ConsumerWidget {
  const _PayoutCard();

  Future<void> _edit(BuildContext context, WidgetRef ref, PayoutDetails? current) async {
    final saved = await showDialog<bool>(context: context, builder: (_) => _PayoutDialog(current: current));
    if (saved == true) {
      ref.invalidate(myPayoutProvider);
      if (context.mounted) showSnack(context, 'Mobile Money details saved');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payout = ref.watch(myPayoutProvider);
    final p = payout.value;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: context.colors.primaryContainer,
          child: Icon(Icons.account_balance_wallet_rounded, color: context.colors.primary),
        ),
        title: Text(p == null ? 'Add your Mobile Money number' : 'Rewards are sent to'),
        subtitle: Text(payout.isLoading && p == null
            ? 'Loading…'
            : p == null
                ? 'So we can send your reward when a company you referred posts its first job.'
                : p.summary),
        trailing: TextButton(onPressed: payout.isLoading ? null : () => _edit(context, ref, p), child: Text(p == null ? 'Add' : 'Change')),
      ),
    );
  }
}

class _PayoutDialog extends ConsumerStatefulWidget {
  const _PayoutDialog({this.current});
  final PayoutDetails? current;

  @override
  ConsumerState<_PayoutDialog> createState() => _PayoutDialogState();
}

class _PayoutDialogState extends ConsumerState<_PayoutDialog> {
  final _key = GlobalKey<FormState>();
  late MobileMoneyProvider _provider = widget.current?.provider ?? MobileMoneyProvider.orange;
  late final _number = TextEditingController(text: widget.current?.displayNumber ?? '');
  late final _name = TextEditingController(text: widget.current?.accountName ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _number.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_key.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref.read(referralBackendProvider).savePayout(_provider, _number.text, _name.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Mobile Money for rewards'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: _key,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SegmentedButton<MobileMoneyProvider>(
                segments: [for (final p in MobileMoneyProvider.values) ButtonSegment(value: p, label: Text(p.label))],
                selected: {_provider},
                onSelectionChanged: (s) => setState(() => _provider = s.first),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _number,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Mobile Money number', hintText: '076 123 456', prefixIcon: Icon(Icons.phone_android_rounded)),
                validator: (v) => PayoutDetails.localDigits(v ?? '') == null ? 'Enter a Sierra Leone mobile number, e.g. 076 123 456' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name on the account', prefixIcon: Icon(Icons.person_outline_rounded)),
                validator: (v) => (v ?? '').trim().length < 3 ? 'Enter the name registered on this number' : null,
              ),
              const SizedBox(height: 10),
              Text('Only you and the Vocation SL team can see this. We use it only to send referral rewards.',
                  style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
          ),
        ],
      );
}