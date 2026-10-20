import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../employer/widgets.dart';
import '../../models/models.dart';
import '../../providers/referral_providers.dart';
import '../../services/export_service.dart';
import '../../widgets/common.dart';
import '../admin_providers.dart';
import '../admin_shell.dart';

/// Employers referred by job seekers: the company, every job it has posted
/// that went live, and whether the referrer has been rewarded.
class AdminReferralsScreen extends ConsumerStatefulWidget {
  const AdminReferralsScreen({super.key});

  @override
  ConsumerState<AdminReferralsScreen> createState() => _AdminReferralsScreenState();
}

class _AdminReferralsScreenState extends ConsumerState<AdminReferralsScreen> {
  ReferralStatus? _filter;
  String _q = '';

  Future<void> _setStatus(Referral r, ReferralStatus status) async {
    final note = await _askNote(
      status == ReferralStatus.rewarded ? 'Mark as rewarded' : status == ReferralStatus.rejected ? 'Mark as not eligible' : 'Change status',
      status == ReferralStatus.rewarded
          ? 'e.g. SLE 50 sent to ${r.payout?.summary ?? 'their Mobile Money'}, transaction ID …'
          : 'Optional note shown to the referrer.',
    );
    if (note == null) return;
    try {
      await ref.read(referralBackendProvider).setStatus(r.id, status, note: note);
      ref.invalidate(adminReferralsProvider);
      if (mounted) showSnack(context, 'Referral updated');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<String?> _askNote(String title, String hint) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, maxLines: 3, decoration: InputDecoration(hintText: hint)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> _editReward(String current) async {
    final c = TextEditingController(text: current);
    final text = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Referral reward'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Shown to job seekers on the Refer an employer screen. Leave empty to show no reward.'),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              maxLines: 3,
              maxLength: 240,
              decoration: const InputDecoration(hintText: 'e.g. Get SLE 200 airtime for each referred company once its first job goes live.'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(d, c.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (text == null) return;
    try {
      await ref.read(referralBackendProvider).saveRewardText(text);
      ref.invalidate(referralRewardProvider);
      if (mounted) showSnack(context, 'Reward text saved');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminReferralsProvider);
    final reward = ref.watch(referralRewardProvider).value ?? '';
    final role = ref.watch(adminRoleProvider).value;
    final canEdit = role?.can(AdminRole.moderator) ?? false;
    final canEditReward = role?.can(AdminRole.admin) ?? false;

    return EmployerPage(
      title: 'Referrals',
      subtitle: 'Companies referred by job seekers, and the jobs each one has posted.',
      onRefresh: () async {
        ref.invalidate(adminReferralsProvider);
        ref.invalidate(referralRewardProvider);
      },
      actions: [
        if (canEdit)
          FilledButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _PayoutList(referrals: (async.value ?? const []).where((r) => r.status == ReferralStatus.qualified).toList()),
            ),
            icon: const Icon(Icons.payments_outlined, size: 18),
            label: const Text('Payouts'),
          ),
        if (canEditReward)
          OutlinedButton.icon(
            onPressed: () => _editReward(reward),
            icon: const Icon(Icons.card_giftcard_rounded, size: 18),
            label: const Text('Reward text'),
          ),
      ],
      children: [
        AdminAsync<List<Referral>>(
          value: async,
          onRetry: () => ref.invalidate(adminReferralsProvider),
          builder: (all) {
            final s = ReferralSummary(all);
            final toReward = all.where((r) => r.status == ReferralStatus.qualified).length;
            final q = _q.trim().toLowerCase();
            final list = all
                .where((r) =>
                    (_filter == null || r.status == _filter) &&
                    (q.isEmpty || '${r.companyName} ${r.referrerName} ${r.referrerEmail} ${r.code}'.toLowerCase().contains(q)))
                .toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              StatGrid(children: [
                StatTile(label: 'Companies referred', value: '${s.total}', icon: Icons.business_rounded, onTap: () => setState(() => _filter = null)),
                StatTile(label: 'Jobs posted', value: '${s.jobsPosted}', detail: 'Live jobs from referred companies', icon: Icons.work_rounded),
                StatTile(
                  label: 'To reward',
                  value: '$toReward',
                  detail: 'Posting jobs, not yet rewarded',
                  icon: Icons.card_giftcard_rounded,
                  attention: toReward > 0,
                  onTap: () => setState(() => _filter = ReferralStatus.qualified),
                ),
                StatTile(label: 'Rewarded', value: '${s.rewarded}', icon: Icons.verified_rounded, onTap: () => setState(() => _filter = ReferralStatus.rewarded)),
              ]),
              const SizedBox(height: 12),
              Text(reward.isEmpty ? 'No reward is shown to job seekers yet.' : 'Reward shown to job seekers: $reward',
                  style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
              const SizedBox(height: 16),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Company, referrer or code', isDense: true),
                    onChanged: (v) => setState(() => _q = v),
                  ),
                ),
                ChoiceChip(label: const Text('All'), selected: _filter == null, onSelected: (_) => setState(() => _filter = null)),
                for (final st in ReferralStatus.values)
                  ChoiceChip(label: Text(st.label), selected: _filter == st, onSelected: (_) => setState(() => _filter = st)),
              ]),
              const SizedBox(height: 16),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(all.isEmpty ? 'No referrals yet.' : 'No referrals match.', style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
                )
              else
                for (final r in list) _AdminReferralCard(referral: r, canEdit: canEdit, onStatus: (st) => _setStatus(r, st)),
            ]);
          },
        ),
      ],
    );
  }
}

class _AdminReferralCard extends StatelessWidget {
  const _AdminReferralCard({required this.referral, required this.canEdit, required this.onStatus});
  final Referral referral;
  final bool canEdit;
  final ValueChanged<ReferralStatus> onStatus;

  @override
  Widget build(BuildContext context) {
    final r = referral;
    final muted = context.text.bodySmall?.copyWith(color: context.palette.muted);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(r.companyName.isEmpty ? 'Company ${r.companyId}' : r.companyName, style: context.text.titleMedium)),
            TagChip(r.status.label, dense: true),
            if (canEdit)
              PopupMenuButton<ReferralStatus>(
                tooltip: 'Change status',
                onSelected: onStatus,
                itemBuilder: (_) => [
                  if (r.status != ReferralStatus.rewarded) const PopupMenuItem(value: ReferralStatus.rewarded, child: Text('Mark as rewarded')),
                  if (r.status != ReferralStatus.rejected) const PopupMenuItem(value: ReferralStatus.rejected, child: Text('Mark as not eligible')),
                  if (r.status == ReferralStatus.rewarded || r.status == ReferralStatus.rejected)
                    PopupMenuItem(
                      value: r.jobs.isEmpty ? ReferralStatus.signedUp : ReferralStatus.qualified,
                      child: const Text('Undo (back to in progress)'),
                    ),
                ],
              ),
          ]),
          const SizedBox(height: 4),
          Text(
            'Referred by ${r.referrerName.isEmpty ? 'a job seeker' : r.referrerName}'
            '${r.referrerEmail.isEmpty ? '' : ' (${r.referrerEmail})'} · code ${ReferralCode.display(r.code)} · joined ${Fmt.dateShort(r.createdAt)}',
            style: muted,
          ),
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.account_balance_wallet_outlined, size: 18, color: r.payout == null ? AppColors.warning : context.colors.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                r.payout == null ? 'No Mobile Money number yet; ask the referrer to add it on Refer an employer' : 'Pay to: ${r.payout!.summary}',
                style: context.text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (r.payout != null)
              IconButton(
                tooltip: 'Copy number',
                icon: const Icon(Icons.copy_rounded, size: 18),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: r.payout!.displayNumber));
                  if (context.mounted) showSnack(context, 'Number copied');
                },
              ),
          ]),
          const SizedBox(height: 10),

          Text('${r.jobsPosted} job${r.jobsPosted == 1 ? '' : 's'} posted', style: context.text.titleSmall),
          for (final j in r.jobs.reversed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(children: [
                const Icon(Icons.work_outline_rounded, size: 16),
                const SizedBox(width: 6),
                Expanded(child: Text(j.title, overflow: TextOverflow.ellipsis)),
                Text(Fmt.dateShort(j.publishedAt), style: muted),
              ]),
            ),
          if (r.rewardedAt != null) ...[
            const SizedBox(height: 8),
            Text('Rewarded ${Fmt.dateShort(r.rewardedAt!)}', style: muted),
          ],
          if (r.note.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Note: ${r.note}', style: context.text.bodySmall),
          ],
        ]),
      ),
    );
  }
}

/// Rewards due (companies whose first job is live, not yet rewarded): who to
/// pay, where, and how much. Download for bulk Mobile Money, then mark paid.
class _PayoutList extends ConsumerStatefulWidget {
  const _PayoutList({required this.referrals});
  final List<Referral> referrals;

  @override
  ConsumerState<_PayoutList> createState() => _PayoutListState();
}

class _PayoutListState extends ConsumerState<_PayoutList> {
  final _ref = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ref.dispose();
    super.dispose();
  }

  List<Referral> get _payable => widget.referrals.where((r) => r.payout != null).toList();

  void _download() {
    ExportService.save(
      'vocation-sl-referral-payouts-${DateTime.now().toIso8601String().substring(0, 10)}.csv',
      ExportService.csv(
        ['Referrer', 'Email', 'Provider', 'Number', 'Name on account', 'Amount (SLE)', 'Company referred', 'Jobs posted', 'Referral id'],
        [
          for (final r in widget.referrals)
            [r.referrerName, r.referrerEmail, r.payout?.provider.label ?? 'NOT GIVEN', r.payout?.displayNumber ?? '', r.payout?.accountName ?? '',
              Referral.rewardAmount, r.companyName, r.jobsPosted, r.id],
        ],
      ),
    );
  }

  Future<void> _markPaid() async {
    final note = _ref.text.trim();
    if (note.isEmpty) {
      showSnack(context, 'Add the payment reference or transaction ID first.', error: true);
      return;
    }
    setState(() => _busy = true);
    var done = 0;
    for (final r in _payable) {
      try {
        await ref.read(referralBackendProvider).setStatus(r.id, ReferralStatus.rewarded,
            note: 'SLE ${Referral.rewardAmount} sent by ${r.payout!.provider.label} to ${r.payout!.displayNumber}. Ref: $note');
        done++;
      } catch (_) {
        // Continue; the summary says how many were marked.
      }
    }
    ref.invalidate(adminReferralsProvider);
    if (!mounted) return;
    Navigator.pop(context);
    showSnack(context, '$done of ${_payable.length} referrals marked as rewarded.');
  }

  @override
  Widget build(BuildContext context) {
    final noNumber = widget.referrals.where((r) => r.payout == null).length;
    return AlertDialog(
      title: const Text('Referral payouts'),
      content: SizedBox(
        width: 560,
        child: widget.referrals.isEmpty
            ? const Text('Nothing to pay right now. Rewards are due once a referred company\'s first job goes live.')
            : SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('${widget.referrals.length} reward${widget.referrals.length == 1 ? '' : 's'} due · '
                      'total SLE ${Fmt.money(Referral.rewardAmount * widget.referrals.length)}',
                      style: context.text.titleSmall),
                  if (noNumber > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('$noNumber referrer${noNumber == 1 ? ' has' : 's have'} no Mobile Money number yet; they\'re skipped when marking paid.',
                          style: context.text.bodySmall?.copyWith(color: AppColors.warning)),
                    ),
                  const SizedBox(height: 8),
                  for (final r in widget.referrals)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text('${r.referrerName.isEmpty ? r.referrerEmail : r.referrerName} · SLE ${Referral.rewardAmount}'),
                      subtitle: Text('${r.payout?.summary ?? 'No Mobile Money number'} · referred ${r.companyName}'),
                    ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _ref,
                    decoration: const InputDecoration(labelText: 'Payment reference or transaction ID', helperText: 'Saved on each referral and sent to the referrer.'),
                  ),
                ]),
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        if (widget.referrals.isNotEmpty) ...[
          OutlinedButton.icon(onPressed: _download, icon: const Icon(Icons.download_rounded), label: const Text('Download list')),
          FilledButton(
            onPressed: _busy || _payable.isEmpty ? null : _markPaid,
            child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text('Mark ${_payable.length} as paid'),
          ),
        ],
      ],
    );
  }
}
