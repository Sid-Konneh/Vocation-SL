import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/core_providers.dart';
import '../../providers/job_providers.dart';
import '../../providers/session_providers.dart';
import '../../providers/user_data_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/company_logo.dart';
import '../../widgets/job_card.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';

class JobDetailsScreen extends ConsumerWidget {
  const JobDetailsScreen({super.key, required this.jobId});
  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(jobDetailProvider(jobId));
    return async.when(
      loading: () => Scaffold(appBar: AppBar(), body: const SingleChildScrollView(child: JobDetailSkeleton())),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorState(error: e, onRetry: () => ref.invalidate(jobDetailProvider(jobId))),
      ),
      data: (loaded) => _JobDetailsView(
        job: loaded.data,
        offline: loaded.isOfflineCopy,
        syncedAt: loaded.syncedAt,
        onRefresh: () => ref.read(jobDetailProvider(jobId).notifier).refresh(),
      ),
    );
  }
}

class _JobDetailsView extends ConsumerWidget {
  const _JobDetailsView({required this.job, required this.offline, required this.syncedAt, required this.onRefresh});
  final Job job;
  final bool offline;
  final DateTime? syncedAt;
  final Future<void> Function() onRefresh;

  Future<void> _share(BuildContext context, WidgetRef ref) async {
    final copied = await ref.read(shareServiceProvider).shareJob(job);
    if (copied && context.mounted) showSnack(context, 'Job details copied to clipboard');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final application = ref.watch(applicationForJobProvider(job.id));
    final user = ref.watch(profileProvider).value?.data;
    final userSkills = user?.skills.map((s) => s.toLowerCase()).toSet() ?? const <String>{};
    final matched = job.skills.where((s) => userSkills.contains(s.toLowerCase())).length;
    final muted = context.palette.muted;
    final c = job.company;

    final body = RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, AppSpacing.gutter, 32),
        children: [
          if (offline) CacheNotice(syncedAt: syncedAt, onRetry: onRefresh),
          Hero(tag: 'logo-${job.id}', child: Align(alignment: Alignment.centerLeft, child: CompanyLogo(company: c, size: 68))),
          const SizedBox(height: 16),
          Semantics(header: true, child: Text(job.title, style: context.text.headlineSmall)),
          const SizedBox(height: 6),
          InkWell(
            onTap: () => context.push('/company/${job.companyId}'),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                Flexible(
                  child: Text(job.companyName,
                      style: context.text.titleMedium?.copyWith(decoration: TextDecoration.underline, fontWeight: FontWeight.w600)),
                ),
                if (c?.verified ?? false) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.verified_rounded, size: 18, color: context.colors.primary, semanticLabel: 'Verified employer'),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 4),
          Text('${job.location}, Sierra Leone · ${Fmt.posted(job.postedAt)} · ${job.applicants} applicants',
              style: context.text.bodyMedium?.copyWith(color: muted)),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            TagChip(job.employmentType.label, icon: Icons.work_outline_rounded),
            TagChip(job.workMode.label, icon: job.workMode == WorkMode.onsite ? Icons.apartment_rounded : Icons.wifi_rounded),
            TagChip(job.experienceLevel.label, icon: Icons.trending_up_rounded),
            TagChip(job.industry.label, icon: Icons.category_outlined),
          ]),
          const SizedBox(height: 20),
          _KeyFacts(job: job),
          if (application != null) ...[
            const SizedBox(height: 16),
            _AppliedBanner(application: application),
          ],
          if (user != null && job.skills.isNotEmpty) ...[
            const SizedBox(height: 16),
            _SkillMatch(matched: matched, total: job.skills.length),
          ],
          _Section('About the job', child: Text(job.about, style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w600))),
          _Section('Description', child: Text(job.description, style: context.text.bodyLarge)),
          if (job.responsibilities.isNotEmpty) _Section('Responsibilities', child: BulletList(job.responsibilities)),
          if (job.requirements.isNotEmpty)
            _Section('Eligibility & requirements', child: BulletList(job.requirements, icon: Icons.check_circle_outline_rounded)),
          if (job.preferred.isNotEmpty)
            _Section('Preferred qualifications', child: BulletList(job.preferred, icon: Icons.add_circle_outline_rounded)),
          if (job.skills.isNotEmpty)
            _Section(
              'Skills',
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in job.skills)
                  userSkills.contains(s.toLowerCase())
                      ? TagChip(s, icon: Icons.check_rounded, color: context.colors.onPrimaryContainer, background: context.colors.primaryContainer)
                      : TagChip(s),
              ]),
            ),
          if (job.benefits.isNotEmpty) _Section('Benefits', child: BulletList(job.benefits, icon: Icons.card_giftcard_rounded)),
          _Section(
            'Salary, location & deadline',
            child: Column(children: [
              InfoRow(icon: Icons.payments_outlined, label: 'Salary', value: Fmt.salary(job)),
              InfoRow(icon: Icons.place_outlined, label: 'Location', value: '${job.location}, Sierra Leone · ${job.workMode.label}'),
              InfoRow(
                icon: Icons.event_outlined,
                label: 'Application deadline',
                value: '${Fmt.date(job.deadline)} · ${Fmt.deadline(job.deadline)}',
              ),
            ]),
          ),
          if (c != null) _Section('About the company', child: _CompanyCard(company: c)),
          const SizedBox(height: 8),
          Text('Job ID: ${job.id.toUpperCase()}', style: context.text.bodySmall?.copyWith(color: muted)),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(tooltip: 'Share job', onPressed: () => _share(context, ref), icon: const Icon(Icons.ios_share_rounded)),
          SaveJobButton(job: job),
          const SizedBox(width: 4),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: AppSpacing.maxReadingWidth), child: body),
      ),
      bottomNavigationBar: _ApplyBar(job: job, application: application),
    );
  }
}

class _KeyFacts extends StatelessWidget {
  const _KeyFacts({required this.job});
  final Job job;

  @override
  Widget build(BuildContext context) {
    final soon = Fmt.deadlineSoon(job.deadline);
    Widget fact(String label, String value, {Color? color}) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: context.text.labelMedium?.copyWith(color: context.palette.muted)),
            const SizedBox(height: 4),
            Text(value, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          fact('Salary', Fmt.salary(job, short: true)),
          fact('Deadline', Fmt.deadline(job.deadline), color: job.isClosed ? AppColors.danger : (soon ? AppColors.warning : null)),
        ]),
        const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider()),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          fact('Job type', job.employmentType.label),
          fact('Experience', job.experienceLevel.label),
        ]),
      ]),
    );
  }
}

class _SkillMatch extends StatelessWidget {
  const _SkillMatch({required this.matched, required this.total});
  final int matched;
  final int total;

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : matched / total;
    final strong = ratio >= 0.5;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.palette.accentTint, borderRadius: BorderRadius.circular(AppSpacing.radius)),
      child: Row(children: [
        SizedBox(
          width: 42,
          height: 42,
          child: Stack(alignment: Alignment.center, children: [
            CircularProgressIndicator(value: ratio, strokeWidth: 4, backgroundColor: context.palette.border),
            Text('$matched/$total', style: context.text.labelSmall?.copyWith(fontWeight: FontWeight.w800)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            strong ? 'Strong match: you have $matched of the $total skills listed.' : 'You have $matched of the $total skills listed. Highlight related experience in your cover letter.',
            style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}

class _AppliedBanner extends StatelessWidget {
  const _AppliedBanner({required this.application});
  final JobApplication application;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          onTap: () => context.push('/application/${application.id}'),
          leading: Icon(StatusChip.iconFor(application.status), color: StatusChip.colorFor(application.status)),
          title: Text(application.pendingSync ? 'Application waiting to send' : 'You applied ${Fmt.ago(application.submittedAt).toLowerCase()}'),
          subtitle: Text('Status: ${application.status.label}'),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
      );
}

class _Section extends StatelessWidget {
  const _Section(this.title, {required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Divider(),
          const SizedBox(height: 24),
          Semantics(header: true, child: Text(title, style: context.text.titleLarge)),
          const SizedBox(height: 14),
          child,
        ]),
      );
}

class _CompanyCard extends StatelessWidget {
  const _CompanyCard({required this.company});
  final Company company;

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onTap: () => context.push('/company/${company.id}'),
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CompanyLogo(company: company, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(company.name, style: context.text.titleMedium),
                    Text('${company.industry.label} · ${company.location}', style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
                  ]),
                ),
              ]),
              const SizedBox(height: 12),
              Text(company.about, maxLines: 4, overflow: TextOverflow.ellipsis, style: context.text.bodyMedium),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                TagChip(company.size, icon: Icons.groups_outlined),
                TagChip('Founded ${company.founded}', icon: Icons.history_edu_outlined),
                TagChip(company.website, icon: Icons.language_rounded),
              ]),
              const SizedBox(height: 12),
              Text('View company and all jobs', style: context.text.labelLarge?.copyWith(decoration: TextDecoration.underline)),
            ]),
          ),
        ),
      );
}

class _ApplyBar extends StatelessWidget {
  const _ApplyBar({required this.job, required this.application});
  final Job job;
  final JobApplication? application;

  @override
  Widget build(BuildContext context) {
    final Widget action;
    if (application != null) {
      action = OutlinedButton.icon(
        onPressed: () => context.push('/application/${application!.id}'),
        icon: const Icon(Icons.track_changes_rounded),
        label: const Text('View application'),
      );
    } else if (job.isClosed) {
      action = const FilledButton(onPressed: null, child: Text('Applications closed'));
    } else {
      action = FilledButton.icon(
        onPressed: () => context.push('/job/${job.id}/apply'),
        icon: const Icon(Icons.send_rounded, size: 20),
        label: const Text('Apply now'),
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.colors.surface,
        border: Border(top: BorderSide(color: context.palette.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 12, AppSpacing.gutter, 12),
          child: Row(children: [
            Expanded(
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(Fmt.salary(job, short: true), style: context.text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(Fmt.deadline(job.deadline), style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
              ]),
            ),
            const SizedBox(width: 12),
            SizedBox(width: 190, child: action),
          ]),
        ),
      ),
    );
  }
}
