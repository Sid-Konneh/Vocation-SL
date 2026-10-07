import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/user_data_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/company_logo.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';
import '../jobs/job_list_sliver.dart';

enum _AppFilter {
  all('All'),
  active('Active'),
  interviews('Interviews'),
  closed('Closed');

  const _AppFilter(this.label);
  final String label;
}

class ApplicationsScreen extends ConsumerStatefulWidget {
  const ApplicationsScreen({super.key});

  @override
  ConsumerState<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends ConsumerState<ApplicationsScreen> {
  _AppFilter _filter = _AppFilter.all;

  bool _matches(JobApplication a) => _matchesFilter(_filter, a);

  static bool _matchesFilter(_AppFilter f, JobApplication a) => switch (f) {
        _AppFilter.all => true,
        _AppFilter.active => a.status.isActive,
        _AppFilter.interviews => a.status == ApplicationStatus.interview || a.status == ApplicationStatus.assessment,
        _AppFilter.closed => a.status.isClosed,
      };

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(applicationsProvider);
    final pad = pagePadding(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Applications')),
      body: async.when(
        loading: () => const SingleChildScrollView(child: ApplicationListSkeleton()),
        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(applicationsProvider)),
        data: (loaded) {
          final all = loaded.data;
          if (all.isEmpty) {
            return RefreshIndicator(
              onRefresh: () => ref.read(applicationsProvider.notifier).refresh(),
              child: ListView(children: [
                const SizedBox(height: 60),
                EmptyState(
                  icon: Icons.work_outline_rounded,
                  title: 'No applications yet',
                  message: 'When you apply for jobs, you can follow every step of the process here.',
                  action: 'Find jobs',
                  onAction: () => context.go('/jobs'),
                ),
              ]),
            );
          }
          final list = all.where(_matches).toList();
          final active = all.where((a) => a.status.isActive).length;
          final interviews = all.where((a) => a.status == ApplicationStatus.interview).length;
          final offers = all.where((a) => a.status == ApplicationStatus.offer || a.status == ApplicationStatus.hired).length;

          return RefreshIndicator(
            onRefresh: () => ref.read(applicationsProvider.notifier).refresh(),
            child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
              SliverPadding(
                padding: pad.copyWith(top: 8),
                sliver: SliverToBoxAdapter(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (loaded.isOfflineCopy)
                      CacheNotice(syncedAt: loaded.syncedAt, onRetry: () => ref.read(applicationsProvider.notifier).refresh()),
                    Row(children: [
                      _Stat(value: active, label: 'Active', color: AppColors.info),
                      const SizedBox(width: 10),
                      _Stat(value: interviews, label: 'Interviews', color: const Color(0xFFD9570F)),
                      const SizedBox(width: 10),
                      _Stat(value: offers, label: 'Offers', color: AppColors.success),
                    ]),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final f in _AppFilter.values)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text('${f.label} (${all.where((a) => _matchesFilter(f, a)).length})'),
                              selected: _filter == f,
                              onSelected: (_) => setState(() => _filter = f),
                              selectedColor: context.colors.onSurface,
                              labelStyle: context.text.labelLarge
                                  ?.copyWith(color: _filter == f ? context.colors.surface : context.colors.onSurface),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 16),
                  ]),
                ),
              ),
              if (list.isEmpty)
                SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.filter_alt_off_outlined,
                    title: 'Nothing here',
                    message: 'No ${_filter.label.toLowerCase()} applications.',
                  ),
                )
              else
                SliverPadding(
                  padding: pad.copyWith(bottom: 32),
                  sliver: SliverList.separated(
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => ApplicationCard(application: list[i]),
                  ),
                ),
            ]),
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label, required this.color});
  final int value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Semantics(
          label: '$value $label',
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(border: Border.all(color: context.palette.border), borderRadius: BorderRadius.circular(AppSpacing.radius)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$value', style: context.text.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: context.text.labelMedium?.copyWith(color: context.palette.muted))),
              ]),
            ]),
          ),
        ),
      );
}

class ApplicationCard extends StatelessWidget {
  const ApplicationCard({super.key, required this.application});
  final JobApplication application;

  @override
  Widget build(BuildContext context) {
    final a = application;
    final job = a.job;
    final pipeline = ApplicationStatus.pipeline;
    final idx = pipeline.indexOf(a.status);
    final progress = a.status.isClosed && idx < 0 ? 1.0 : (idx + 1) / pipeline.length;
    final color = StatusChip.colorFor(a.status);

    String? nextStep;
    if (a.pendingSync) {
      nextStep = 'Waiting to send · will submit when you\'re back online';
    } else if (a.interviewAt != null && a.status == ApplicationStatus.interview) {
      nextStep = 'Interview ${Fmt.dateTime(a.interviewAt!)}';
    } else if (a.nextStepDeadline != null && a.status.isActive) {
      nextStep = 'Due ${Fmt.dateTime(a.nextStepDeadline!)}';
    } else if (a.employerMessage != null && a.status.isActive) {
      nextStep = 'New message from employer';
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/application/${a.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CompanyLogo(company: job?.company, size: 44, name: job?.companyName),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(job?.title ?? 'Job no longer listed', style: context.text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                  Text('${job?.companyName ?? ''} · ${job?.location ?? ''}',
                      style: context.text.bodySmall?.copyWith(color: context.palette.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                ]),
              ),
            ]),
            const SizedBox(height: 14),
            Row(children: [
              Flexible(child: StatusChip(a.status, dense: true)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Applied ${Fmt.dateShort(a.submittedAt)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: context.text.labelSmall?.copyWith(color: context.palette.muted),
                ),
              ),
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 5,
                color: a.status == ApplicationStatus.withdrawn ? context.palette.muted : color,
                backgroundColor: context.palette.border,
                semanticsLabel: 'Application progress: ${a.status.label}',
                semanticsValue: '${(progress * 100).round()}',
              ),
            ),
            if (nextStep != null) ...[
              const SizedBox(height: 12),
              Row(children: [
                Icon(a.pendingSync ? Icons.cloud_upload_outlined : Icons.arrow_forward_rounded, size: 16, color: context.colors.primary),
                const SizedBox(width: 6),
                Expanded(child: Text(nextStep, style: context.text.labelMedium?.copyWith(color: context.colors.primary))),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}
