import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../employer/charts.dart';
import '../../employer/widgets.dart';
import '../../models/models.dart';
import '../../widgets/skeletons.dart';
import '../admin_providers.dart';
import '../admin_shell.dart';

final _n = NumberFormat.decimalPattern('en');
String _pct(double? v) => v == null ? '—' : '${(v * 100).toStringAsFixed(1)}%';

/// Turns database values (e.g. "fullTime", "technology") into readable labels.
String _label(String raw) {
  for (final values in [Industry.values, EmploymentType.values, WorkMode.values, ExperienceLevel.values, ApplicationStatus.values, CompanyStatus.values]) {
    for (final v in values) {
      if (v.name == raw) {
        return switch (v) {
          Industry i => i.label,
          EmploymentType e => e.label,
          WorkMode w => w.label,
          ExperienceLevel x => x.label,
          ApplicationStatus s => s.label,
          CompanyStatus c => c.label,
          _ => raw,
        };
      }
    }
  }
  return raw;
}

List<({String label, int count})> _items(List<CountPoint> points) => [for (final p in points) (label: _label(p.label), count: p.count)];

Widget _twoUp(List<Widget> cards) => LayoutBuilder(builder: (context, c) {
      if (c.maxWidth < 900) {
        return Column(children: [for (final w in cards) Padding(padding: const EdgeInsets.only(bottom: 16), child: w)]);
      }
      final rows = <Widget>[];
      for (var i = 0; i < cards.length; i += 2) {
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: cards[i]),
              const SizedBox(width: 16),
              Expanded(child: i + 1 < cards.length ? cards[i + 1] : const SizedBox()),
            ]),
          ),
        ));
      }
      return Column(children: rows);
    });

Widget _heading(BuildContext context, String t, [String? sub]) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Semantics(header: true, child: Text(t, style: context.text.titleLarge)),
        if (sub != null) Text(sub, style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
      ]),
    );

class AdminOverviewScreen extends ConsumerWidget {
  const AdminOverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(adminStatsProvider);
    final activity = ref.watch(adminActivityProvider);
    return EmployerPage(
      title: 'Overview',
      subtitle: 'What needs attention, and how Vocation SL is doing.',
      onRefresh: () async {
        ref.invalidate(adminStatsProvider);
        ref.invalidate(adminActivityProvider);
        await ref.read(adminStatsProvider.future);
      },
      children: [
        AdminAsync<AdminStats>(
          skeleton: const DashboardSkeleton(),
          value: stats,
          onRetry: () => ref.invalidate(adminStatsProvider),
          builder: (s) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _heading(context, 'Needs attention', s.pendingWork == 0 ? 'All caught up.' : '${s.pendingWork} items waiting for review'),
            StatGrid(children: [
              StatTile(
                label: 'Employers to verify',
                value: '${s.companiesPending}',
                icon: Icons.verified_user_outlined,
                attention: s.companiesPending > 0,
                onTap: () => context.go('/admin/employers'),
              ),
              StatTile(
                label: 'Jobs awaiting approval',
                value: '${s.jobsPending}',
                icon: Icons.fact_check_outlined,
                attention: s.jobsPending > 0,
                onTap: () => context.go('/admin/jobs'),
              ),
              StatTile(
                label: 'Open reports',
                value: '${s.reportsOpen}',
                detail: '${s.reportsTotal} all time',
                icon: Icons.flag_outlined,
                attention: s.reportsOpen > 0,
                onTap: () => context.go('/admin/reports'),
              ),
              StatTile(
                label: 'Jobs closing this week',
                value: '${s.jobsClosing7d}',
                icon: Icons.event_busy_outlined,
                onTap: () => context.go('/admin/jobs'),
              ),
              StatTile(label: 'Suspended accounts', value: '${s.suspended}', icon: Icons.block_outlined, onTap: () => context.go('/admin/users')),
            ]),
            _heading(context, 'Platform'),
            StatGrid(children: [
              StatTile(label: 'Users', value: _n.format(s.usersTotal), detail: '+${s.newUsers7d} this week', icon: Icons.people_outline_rounded),
              StatTile(label: 'Active this week', value: _n.format(s.activeUsers7d), detail: 'Signed in in the last 7 days', icon: Icons.bolt_outlined),
              StatTile(label: 'Job seekers', value: _n.format(s.seekers), icon: Icons.person_search_outlined),
              StatTile(label: 'Employers', value: _n.format(s.employers), detail: '${s.companiesTotal} companies', icon: Icons.business_outlined),
              StatTile(
                label: 'Verified companies',
                value: '${s.companiesVerified}',
                detail: 'Approval rate ${_pct(s.approvalRate)}',
                icon: Icons.verified_outlined,
              ),
              StatTile(label: 'Live jobs', value: _n.format(s.jobsLive), detail: '${s.jobsFeatured} featured · ${s.jobsTotal} total', icon: Icons.work_outline_rounded),
              StatTile(label: 'Applications', value: _n.format(s.applicationsTotal), detail: '+${s.applications7d} this week', icon: Icons.inbox_outlined),
              StatTile(label: 'Hires', value: _n.format(s.hires), detail: '${s.hires30d} in the last 30 days', icon: Icons.handshake_outlined),
              StatTile(label: 'Job views', value: _n.format(s.jobViews), detail: 'View → apply ${_pct(s.viewToApply)}', icon: Icons.visibility_outlined),
              StatTile(
                label: 'Avg. first response',
                value: s.avgResponseDays == null ? '—' : '${s.avgResponseDays!.toStringAsFixed(1)} days',
                detail: 'Employer reply time',
                icon: Icons.timer_outlined,
                attention: (s.avgResponseDays ?? 0) > 7,
              ),
              StatTile(label: 'Applicants per job', value: s.applicationsPerJob.toStringAsFixed(1), icon: Icons.groups_outlined),
              StatTile(
                label: 'Avg. advertised salary',
                value: s.avgSalary == 0 ? '—' : 'SLE ${_n.format(s.avgSalary)}',
                detail: 'Per month, live jobs',
                icon: Icons.payments_outlined,
              ),
            ]),
            const SizedBox(height: 16),
            _twoUp([
              SectionCard(title: 'New signups', child: DailyApplicationsChart(days: s.signups30d, noun: 'signup')),
              SectionCard(title: 'Applications', child: DailyApplicationsChart(days: s.applications30d)),
            ]),
          ]),
        ),
        SectionCard(
          title: 'Recent admin activity',
          trailing: TextButton(onPressed: () => context.go('/admin/activity'), child: const Text('View all')),
          child: AdminAsync<List<AuditEntry>>(
            value: activity,
            onRetry: () => ref.invalidate(adminActivityProvider),
            builder: (list) => list.isEmpty
                ? Text('No admin actions yet.', style: context.text.bodyMedium)
                : Column(children: [
                    for (final e in list.take(8))
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        leading: const Icon(Icons.history_rounded),
                        title: Text(e.summary, maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text('${e.actorEmail.isEmpty ? 'System' : e.actorEmail} · ${Fmt.ago(e.createdAt)}'),
                      ),
                  ]),
          ),
        ),
      ],
    );
  }
}

class AdminInsightsScreen extends ConsumerWidget {
  const AdminInsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(adminStatsProvider);
    return EmployerPage(
      title: 'Insights',
      subtitle: 'Trends across job seekers, employers, jobs and applications.',
      onRefresh: () async {
        ref.invalidate(adminStatsProvider);
        await ref.read(adminStatsProvider.future);
      },
      children: [
        AdminAsync<AdminStats>(
          skeleton: const DashboardSkeleton(),
          value: stats,
          onRetry: () => ref.invalidate(adminStatsProvider),
          builder: (s) {
            final companyStatus = [
              (label: 'Approved', count: s.companiesApproved),
              (label: 'Awaiting approval', count: s.companiesPending),
              (label: 'Not approved', count: s.companiesRejected),
              (label: 'Suspended', count: s.companiesSuspended),
            ].where((e) => e.count > 0).toList();
            final jobStatus = [
              (label: 'Live', count: s.jobsLive),
              (label: 'Awaiting approval', count: s.jobsPending),
              (label: 'Closed or expired', count: s.jobsClosed),
              (label: 'Drafts', count: s.jobsDraft),
            ].where((e) => e.count > 0).toList();
            final pipeline = [
              for (final st in ApplicationStatus.values)
                if ((s.byStatus[st.name] ?? 0) > 0) (label: st.label, count: s.byStatus[st.name]!),
            ];
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _heading(context, 'Growth', 'Last 30 days'),
              _twoUp([
                SectionCard(title: 'New signups', child: DailyApplicationsChart(days: s.signups30d, noun: 'signup')),
                SectionCard(title: 'Jobs posted', child: DailyApplicationsChart(days: s.jobs30d, noun: 'job')),
                SectionCard(title: 'Applications', child: DailyApplicationsChart(days: s.applications30d)),
                SectionCard(
                  title: 'Marketplace health',
                  child: Column(children: [
                    _Metric('Applicants per posted job', s.applicationsPerJob.toStringAsFixed(1)),
                    _Metric('Job views that became applications', _pct(s.viewToApply)),
                    _Metric('Employer approval rate', _pct(s.approvalRate)),
                    _Metric('Average first response', s.avgResponseDays == null ? '—' : '${s.avgResponseDays!.toStringAsFixed(1)} days'),
                    _Metric('Hires (last 30 days)', '${s.hires30d}'),
                    _Metric('Active users (last 7 days)', '${s.activeUsers7d} of ${s.usersTotal}'),
                    _Metric('Average advertised salary', s.avgSalary == 0 ? '—' : 'SLE ${_n.format(s.avgSalary)} / month'),
                  ]),
                ),
              ]),
              _heading(context, 'Jobs', 'Live jobs only'),
              _twoUp([
                SectionCard(title: 'By industry', child: RankedBars(items: _items(s.topIndustries))),
                SectionCard(title: 'By location', child: RankedBars(items: _items(s.topLocations))),
                SectionCard(title: 'By job type', child: RankedBars(items: _items(s.byEmploymentType))),
                SectionCard(title: 'By work mode', child: RankedBars(items: _items(s.byWorkMode))),
                SectionCard(title: 'By experience level', child: RankedBars(items: _items(s.byExperience))),
                SectionCard(title: 'All jobs by status', child: RankedBars(items: jobStatus)),
              ]),
              _heading(context, 'Hiring pipeline', 'All applications by current stage'),
              _twoUp([
                SectionCard(title: 'Applications by stage', child: RankedBars(items: pipeline, empty: 'No applications yet.')),
                SectionCard(title: 'Top employers by applicants', child: RankedBars(items: _items(s.topCompanies), empty: 'No applications yet.')),
              ]),
              _heading(context, 'People'),
              _twoUp([
                SectionCard(title: 'Where job seekers are based', child: RankedBars(items: _items(s.seekerLocations))),
                SectionCard(title: 'Companies by status', child: RankedBars(items: companyStatus)),
              ]),
              _heading(context, 'Trust & safety'),
              _twoUp([
                SectionCard(title: 'Reports by reason', child: RankedBars(items: _items(s.reportsByReason), empty: 'No reports yet.')),
                SectionCard(
                  title: 'Moderation',
                  child: Column(children: [
                    _Metric('Open reports', '${s.reportsOpen}'),
                    _Metric('Reports all time', '${s.reportsTotal}'),
                    _Metric('Suspended accounts', '${s.suspended}'),
                    _Metric('Suspended companies', '${s.companiesSuspended}'),
                  ]),
                ),
              ]),
            ]);
          },
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Expanded(child: Text(label, style: context.text.bodyMedium)),
          Text(value, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      );
}
