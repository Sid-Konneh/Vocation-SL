import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../employer/widgets.dart';
import '../../features/support/support_screens.dart';
import '../../models/models.dart';
import '../../providers/hiring_providers.dart';
import '../../widgets/common.dart';
import '../admin_shell.dart';

/// Support requests from job seekers and employers.
class AdminSupportScreen extends ConsumerStatefulWidget {
  const AdminSupportScreen({super.key});

  @override
  ConsumerState<AdminSupportScreen> createState() => _AdminSupportScreenState();
}

class _AdminSupportScreenState extends ConsumerState<AdminSupportScreen> {
  SupportStatus? _filter = SupportStatus.open;
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(allTicketsProvider);
    final canReply = adminCan(ref, AdminRole.moderator);
    return EmployerPage(
      title: 'Support inbox',
      subtitle: 'Questions and problems sent from the app. Replies reach the person as a notification.',
      onRefresh: () async => ref.invalidate(allTicketsProvider),
      children: [
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          for (final f in [SupportStatus.open, SupportStatus.answered, SupportStatus.closed, null])
            ChoiceChip(
              label: Text(
                '${f == null ? 'All' : (f == SupportStatus.open ? 'Needs a reply' : f.label)}'
                ' (${(async.value ?? const []).where((t) => f == null || t.status == f).length})',
              ),
              selected: _filter == f,
              onSelected: (_) => setState(() => _filter = f),
            ),
          SizedBox(
            width: 260,
            child: TextField(
              onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
              decoration: const InputDecoration(hintText: 'Search subject, name or email', prefixIcon: Icon(Icons.search_rounded), isDense: true),
            ),
          ),
        ]),
        if (!canReply) ...[
          const SizedBox(height: 8),
          Text('Viewers can read requests; moderators and above can reply.', style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
        ],
        const SizedBox(height: 16),
        AdminAsync<List<SupportTicket>>(
          value: async,
          onRetry: () => ref.invalidate(allTicketsProvider),
          builder: (all) {
            final list = all
                .where((t) => _filter == null || t.status == _filter)
                .where((t) => _q.isEmpty || '${t.subject} ${t.userName} ${t.userEmail}'.toLowerCase().contains(_q))
                .toList();
            if (list.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_filter == SupportStatus.open ? 'Nothing waiting for a reply.' : 'No requests here.', style: context.text.bodyLarge),
                ),
              );
            }
            return Column(children: [
              for (final t in list)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => SupportThreadScreen(ticketId: t.id, staff: true, ticket: t),
                    )),
                    leading: Icon(t.side == UserRole.employer ? Icons.business_outlined : Icons.person_outline_rounded),
                    title: Text(t.subject, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      [t.userName.isNotEmpty ? t.userName : t.userEmail, t.category.label, Fmt.ago(t.lastMessageAt)].where((s) => s.isNotEmpty).join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: SupportStatusChip(t.status, staffView: true),
                  ),
                ),
            ]);
          },
        ),
      ],
    );
  }
}

/// The last 7 days at a glance. Owners and admins also get it as a
/// notification every Monday morning.
class AdminDigestScreen extends ConsumerWidget {
  const AdminDigestScreen({super.key});

  static String _change(int now, int before) {
    if (now == before) return 'Same as the week before';
    return '${now > before ? 'Up' : 'Down'} from ${Fmt.money(before)} the week before';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(weeklyDigestProvider);
    return EmployerPage(
      title: 'Weekly digest',
      subtitle: 'The last 7 days. Owners and admins get this as a notification every Monday at 07:00.',
      onRefresh: () async => ref.invalidate(weeklyDigestProvider),
      actions: [
        if (adminCan(ref, AdminRole.admin))
          OutlinedButton.icon(
            onPressed: () async {
              try {
                final n = await ref.read(hiringBackendProvider).sendDigestNow();
                if (context.mounted) showSnack(context, 'Digest notification sent to $n ${n == 1 ? 'person' : 'people'}');
              } catch (e) {
                if (context.mounted) showError(context, e);
              }
            },
            icon: const Icon(Icons.notifications_active_outlined),
            label: const Text('Send notification now'),
          ),
      ],
      children: [
        AdminAsync<WeeklyDigest>(
          value: async,
          onRetry: () => ref.invalidate(weeklyDigestProvider),
          builder: (d) {
            Widget tile(String label, String value, {String? detail, IconData? icon, String? go, bool attention = false}) => StatTile(
                  label: label,
                  value: value,
                  detail: detail,
                  icon: icon,
                  attention: attention,
                  onTap: go == null ? null : () => context.go(go),
                );
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (d.from != null && d.to != null)
                Text('${Fmt.date(d.from!)} – ${Fmt.date(d.to!)}', style: context.text.titleSmall?.copyWith(color: context.palette.muted)),
              const SizedBox(height: 12),
              Text('Growth', style: context.text.titleMedium),
              const SizedBox(height: 8),
              StatGrid(children: [
                tile('New users', Fmt.money(d.n('new_users')), detail: _change(d.n('new_users'), d.n('new_users_prev')), icon: Icons.person_add_alt_rounded, go: '/admin/users'),
                tile('New employers', Fmt.money(d.n('new_employers')),
                    detail: _change(d.n('new_employers'), d.n('new_employers_prev')), icon: Icons.business_outlined, go: '/admin/employers'),
                tile('Jobs that went live', Fmt.money(d.n('jobs_new')), detail: _change(d.n('jobs_new'), d.n('jobs_new_prev')), icon: Icons.work_outline_rounded, go: '/admin/jobs'),
                tile('Applications', Fmt.money(d.n('applications')),
                    detail: _change(d.n('applications'), d.n('applications_prev')), icon: Icons.assignment_outlined, go: '/admin/applications'),
                tile('Live jobs now', Fmt.money(d.n('jobs_live')), icon: Icons.public_rounded),
              ]),
              if (d.newEmployerNames.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('New employers: ${d.newEmployerNames.join(', ')}', style: context.text.bodyMedium),
              ],
              const SizedBox(height: 20),
              Text('Money', style: context.text.titleMedium),
              const SizedBox(height: 8),
              StatGrid(children: [
                tile('Received (incl. GST)', 'SLE ${Fmt.money(d.n('revenue_paid'))}',
                    detail: 'SLE ${Fmt.money(d.n('revenue_paid_prev'))} the week before', icon: Icons.payments_outlined, go: '/admin/invoices'),
                tile('Unpaid invoices', '${d.n('unpaid_count')}',
                    detail: 'SLE ${Fmt.money(d.n('unpaid_total'))}${d.n('overdue_count') > 0 ? ' · ${d.n('overdue_count')} overdue' : ''}',
                    icon: Icons.receipt_long_outlined,
                    go: '/admin/invoices',
                    attention: d.n('overdue_count') > 0),
                tile('Referral rewards to pay', '${d.n('referrals_to_pay')}', icon: Icons.handshake_outlined, go: '/admin/referrals', attention: d.n('referrals_to_pay') > 0),
              ]),
              const SizedBox(height: 20),
              Text('Needs attention', style: context.text.titleMedium),
              const SizedBox(height: 8),
              StatGrid(children: [
                tile('Employers to approve', '${d.n('companies_pending')}', icon: Icons.verified_user_outlined, go: '/admin/employers', attention: d.n('companies_pending') > 0),
                tile('Jobs to review', '${d.n('jobs_pending')}', icon: Icons.fact_check_outlined, go: '/admin/jobs', attention: d.n('jobs_pending') > 0),
                tile('Jobs with scam warning signs', '${d.n('flagged_jobs')}',
                    detail: 'Posted this week', icon: Icons.gpp_maybe_outlined, go: '/admin/jobs', attention: d.n('flagged_jobs') > 0),
                tile('Open reports', '${d.n('reports_open')}', icon: Icons.flag_outlined, go: '/admin/reports', attention: d.n('reports_open') > 0),
                tile('Support requests waiting', '${d.n('support_open')}', icon: Icons.support_agent_rounded, go: '/admin/support', attention: d.n('support_open') > 0),
              ]),
              const SizedBox(height: 12),
              Text('Scam warning signs are a keyword check (fees, Mobile Money PINs, WhatsApp-only, short links). A flagged job may be genuine.',
                  style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
            ]);
          },
        ),
      ],
    );
  }
}
