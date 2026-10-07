import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/models.dart';
import '../../../widgets/common.dart';
import '../../../widgets/states.dart';
import '../../charts.dart';
import '../../providers.dart';
import '../../widgets.dart';
import '../company/company_screens.dart';

Future<void> _refreshAll(WidgetRef ref) async {
  await Future.wait([
    ref.read(employerJobsProvider.notifier).refresh(),
    ref.read(candidatesProvider.notifier).refresh(),
  ]);
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final company = ref.watch(companyProvider).value?.data;
    final stats = ref.watch(hiringStatsProvider);
    final apps = ref.watch(candidatesProvider).value?.data ?? const <JobApplication>[];
    final jobs = ref.watch(employerJobsProvider).value?.data ?? const <Job>[];
    final loading = ref.watch(candidatesProvider).isLoading && apps.isEmpty;
    final h = DateTime.now().hour;
    final greeting = h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
    final closingSoon = jobs.where((j) => j.status == JobStatus.published && Fmt.deadlineSoon(j.deadline)).toList();
    final wide = MediaQuery.sizeOf(context).width >= 1100;

    final recent = SectionCard(
      title: 'Recent applicants',
      trailing: TextButton(onPressed: () => context.go('/employer/candidates'), child: const Text('View all')),
      child: apps.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(loading ? 'Loading…' : 'No applicants yet. Share your job links to get started.', style: context.text.bodyMedium),
            )
          : Column(children: [
              for (final a in apps.take(6))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => context.push('/employer/candidates/${a.id}'),
                  leading: UserAvatar(initials: a.applicant.fullName.isEmpty ? '?' : a.applicant.fullName[0].toUpperCase(), size: 36),
                  title: Text(a.applicant.fullName, style: context.text.titleSmall?.copyWith(fontWeight: a.status == ApplicationStatus.applied ? FontWeight.w800 : null)),
                  subtitle: Text('${a.job?.title ?? ''} · ${Fmt.ago(a.submittedAt)}', maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: StatusChip(a.status, dense: true),
                ),
            ]),
    );

    final interviews = SectionCard(
      title: 'Upcoming interviews',
      child: stats.upcomingInterviews.isEmpty
          ? Text('None scheduled. Open a candidate to schedule one.', style: context.text.bodyMedium)
          : Column(children: [
              for (final a in stats.upcomingInterviews.take(5))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => context.push('/employer/candidates/${a.id}'),
                  leading: const Icon(Icons.event_rounded),
                  title: Text(a.applicant.fullName),
                  subtitle: Text('${Fmt.dateTime(a.interviewAt!)} · ${a.job?.title ?? ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
            ]),
    );

    final closing = SectionCard(
      title: 'Closing soon',
      child: closingSoon.isEmpty
          ? Text('No live jobs close in the next few days.', style: context.text.bodyMedium)
          : Column(children: [
              for (final j in closingSoon)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  onTap: () => context.push('/employer/jobs/${j.id}/edit'),
                  title: Text(j.title),
                  subtitle: Text('${j.applicants} applicants'),
                  trailing: Text(Fmt.deadline(j.deadline), style: const TextStyle(color: AppColors.warning, fontWeight: FontWeight.w700)),
                ),
            ]),
    );

    return EmployerPage(
      title: '$greeting${company == null ? '' : ', ${company.name}'}',
      subtitle: 'Here\'s how your hiring is going.',
      onRefresh: () => _refreshAll(ref),
      actions: [
        FilledButton.icon(
          onPressed: () => context.push('/employer/jobs/new'),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Post a job'),
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
        ),
      ],
      children: [
        if (company != null) ApprovalBanner(company: company),
        StatGrid(children: [
          StatTile(label: 'Live jobs', value: '${stats.liveJobs}', detail: stats.pendingJobs > 0 ? '${stats.pendingJobs} awaiting approval' : '${stats.draftJobs} drafts', icon: Icons.work_outline_rounded, onTap: () => context.go('/employer/jobs')),
          StatTile(label: 'Applicants', value: '${stats.totalApplicants}', detail: '${stats.newThisWeek} this week', icon: Icons.people_outline_rounded, onTap: () => context.go('/employer/candidates')),
          StatTile(label: 'To review', value: '${stats.awaitingReview}', detail: 'New, not yet opened', icon: Icons.mark_email_unread_outlined, attention: stats.awaitingReview > 0, onTap: () => context.go('/employer/candidates')),
          StatTile(label: 'Interviews', value: '${stats.upcomingInterviews.length}', detail: 'Upcoming', icon: Icons.event_outlined),
        ]),
        const SizedBox(height: 16),
        if (wide)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: Column(children: [recent, const SizedBox(height: 16), SectionCard(title: 'Hiring funnel', child: FunnelChart(funnel: stats.funnel))])),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: Column(children: [interviews, const SizedBox(height: 16), closing])),
          ])
        else ...[
          recent,
          const SizedBox(height: 16),
          interviews,
          const SizedBox(height: 16),
          SectionCard(title: 'Hiring funnel', child: FunnelChart(funnel: stats.funnel)),
          const SizedBox(height: 16),
          closing,
        ],
      ],
    );
  }
}

class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(hiringStatsProvider);
    final async = ref.watch(candidatesProvider);
    final perf = stats.jobPerformance;
    final applicants = perf.fold(0, (s, p) => s + p.applicants);
    final conversion = stats.totalViews == 0 ? null : applicants / stats.totalViews;
    final response = stats.averageResponseDays;
    final byStatus = stats.byStatus;

    return EmployerPage(
      title: 'Insights',
      subtitle: 'Views, applications and how candidates move through your pipeline.',
      onRefresh: () => _refreshAll(ref),
      children: [
        if (async.hasError && !async.hasValue) ErrorState(error: async.error!, onRetry: () => ref.invalidate(candidatesProvider)),
        StatGrid(children: [
          StatTile(label: 'Job views', value: '${stats.totalViews}', detail: 'All posted jobs', icon: Icons.visibility_outlined),
          StatTile(label: 'Applications', value: '$applicants', icon: Icons.inbox_outlined),
          StatTile(
            label: 'View → apply',
            value: conversion == null ? '—' : '${(conversion * 100).toStringAsFixed(1)}%',
            detail: conversion == null ? 'No views yet' : 'Share of viewers who applied',
            icon: Icons.trending_up_rounded,
          ),
          StatTile(
            label: 'Avg. first response',
            value: response == null ? '—' : '${response.toStringAsFixed(1)} days',
            detail: 'Applied → first stage change',
            icon: Icons.timer_outlined,
            attention: response != null && response > 7,
          ),
          StatTile(label: 'Hires', value: '${stats.hires}', icon: Icons.verified_outlined),
        ]),
        const SizedBox(height: 16),
        SectionCard(title: 'Applications per day', child: DailyApplicationsChart(days: stats.dailyApplications())),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, c) {
          final funnel = SectionCard(title: 'Hiring funnel', child: FunnelChart(funnel: stats.funnel));
          final statuses = SectionCard(
            title: 'Where candidates are now',
            child: Column(children: [
              for (final e in byStatus.entries.where((e) => e.value > 0))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [StatusChip(e.key, dense: true), const Spacer(), Text('${e.value}', style: context.text.titleSmall)]),
                ),
              if (byStatus.values.every((v) => v == 0)) Text('No applications yet.', style: context.text.bodyMedium),
            ]),
          );
          if (c.maxWidth < 900) return Column(children: [funnel, const SizedBox(height: 16), statuses]);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: funnel),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: statuses),
          ]);
        }),
        const SizedBox(height: 16),
        Text('Job performance', style: context.text.titleLarge),
        const SizedBox(height: 12),
        TableCard(
          empty: const EmptyState(icon: Icons.insights_outlined, title: 'No posted jobs yet', message: 'Performance appears here once your jobs are live.'),
          columns: const [
            DataColumn(label: Text('Job')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Views'), numeric: true),
            DataColumn(label: Text('Applicants'), numeric: true),
            DataColumn(label: Text('View → apply'), numeric: true),
            DataColumn(label: Text('Shortlisted'), numeric: true),
            DataColumn(label: Text('Hired'), numeric: true),
          ],
          rows: [
            for (final p in perf)
              DataRow(
                onSelectChanged: (_) => context.go('/employer/candidates?job=${p.job.id}'),
                cells: [
                  DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 260), child: Text(p.job.title, maxLines: 2, overflow: TextOverflow.ellipsis))),
                  DataCell(JobStatusPill(p.job.status)),
                  DataCell(Text('${p.views}')),
                  DataCell(Text('${p.applicants}')),
                  DataCell(Text(p.conversion == null ? '—' : '${(p.conversion! * 100).toStringAsFixed(1)}%')),
                  DataCell(Text('${p.shortlisted}')),
                  DataCell(Text('${p.hired}')),
                ],
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text('Views are counted when a signed-in or anonymous visitor opens a job.', style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
      ],
    );
  }
}
