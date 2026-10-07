import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/user_data_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';
import '../jobs/job_list_sliver.dart';

class SavedScreen extends StatelessWidget {
  const SavedScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Saved'),
            bottom: const TabBar(tabs: [Tab(text: 'Jobs'), Tab(text: 'Searches & alerts')]),
          ),
          body: const TabBarView(children: [_SavedJobs(), _SavedSearches()]),
        ),
      );
}

class _SavedJobs extends ConsumerWidget {
  const _SavedJobs();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(savedJobsProvider);
    final pad = pagePadding(context);
    return async.when(
      loading: () => SingleChildScrollView(child: JobListSkeleton(count: 3, padding: pad.copyWith(top: 16))),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(savedJobsProvider)),
      data: (loaded) {
        final saved = loaded.data;
        final jobs = saved.where((s) => s.job != null).map((s) => s.job!).toList();
        return RefreshIndicator(
          onRefresh: () => ref.read(savedJobsProvider.notifier).refresh(),
          child: CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), slivers: [
            if (loaded.isOfflineCopy)
              SliverPadding(
                padding: pad.copyWith(top: 12),
                sliver: SliverToBoxAdapter(child: CacheNotice(syncedAt: loaded.syncedAt, onRetry: () => ref.read(savedJobsProvider.notifier).refresh())),
              ),
            if (jobs.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.bookmark_border_rounded,
                  title: 'No saved jobs',
                  message: 'Tap the bookmark on any job to save it here and come back to it later, even offline.',
                  action: 'Browse jobs',
                  onAction: () => context.go('/jobs'),
                ),
              )
            else ...[
              SliverPadding(
                padding: pad.copyWith(top: 16, bottom: 12),
                sliver: SliverToBoxAdapter(
                  child: Text('${jobs.length} saved job${jobs.length == 1 ? '' : 's'}', style: context.text.titleMedium),
                ),
              ),
              SliverPadding(padding: pad.copyWith(bottom: 32), sliver: JobListSliver(jobs: jobs)),
            ],
          ]),
        );
      },
    );
  }
}

class _SavedSearches extends ConsumerWidget {
  const _SavedSearches();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(alertsProvider);
    final pad = pagePadding(context);
    return async.when(
      loading: () => Skeleton(
        child: Padding(padding: pad.copyWith(top: 16), child: const Column(children: [ListTileSkeleton(trailing: true), ListTileSkeleton(trailing: true)])),
      ),
      error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(alertsProvider)),
      data: (loaded) {
        final alerts = loaded.data;
        return RefreshIndicator(
          onRefresh: () => ref.read(alertsProvider.notifier).refresh(),
          child: alerts.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 40),
                  EmptyState(
                    icon: Icons.notifications_active_outlined,
                    title: 'No saved searches',
                    message: 'Search for jobs, then tap "Save search & get alerts" to hear about new matches.',
                    action: 'Search jobs',
                    onAction: () => context.push('/search'),
                  ),
                ])
              : ListView.separated(
                  padding: pad.copyWith(top: 16, bottom: 32),
                  itemCount: alerts.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _AlertCard(alert: alerts[i]),
                ),
        );
      },
    );
  }
}

class _AlertCard extends ConsumerWidget {
  const _AlertCard({required this.alert});
  final JobAlert alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(alertsProvider.notifier);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        onTap: () => context.push('/search', extra: alert.filter),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.manage_search_rounded, color: context.colors.primary),
              const SizedBox(width: 10),
              Expanded(child: Text(alert.name, style: context.text.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis)),
              Switch(
                value: alert.enabled,
                onChanged: (v) => ctrl.updateAlert(alert.copyWith(enabled: v)),
              ),
              PopupMenuButton<String>(
                tooltip: 'More options',
                onSelected: (v) async {
                  if (v == 'delete') {
                    final ok = await confirmDialog(context,
                        title: 'Delete saved search?', message: 'You\'ll stop getting alerts for "${alert.name}".', confirmLabel: 'Delete', destructive: true);
                    if (ok) await ctrl.delete(alert.id);
                  } else {
                    final f = AlertFrequency.values.byName(v);
                    await ctrl.updateAlert(alert.copyWith(frequency: f));
                  }
                },
                itemBuilder: (_) => [
                  for (final f in AlertFrequency.values)
                    CheckedPopupMenuItem(value: f.name, checked: alert.frequency == f, child: Text('Alert ${f.label.toLowerCase()}')),
                  const PopupMenuDivider(),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(left: 34, right: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(alert.filter.summary, style: context.text.bodyMedium?.copyWith(color: context.palette.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 8),
                Row(children: [
                  TagChip(alert.enabled ? 'Alerts ${alert.frequency.label.toLowerCase()}' : 'Alerts paused',
                      dense: true, icon: alert.enabled ? Icons.notifications_active_outlined : Icons.notifications_off_outlined),
                  const SizedBox(width: 8),
                  Text('Saved ${Fmt.dateShort(alert.createdAt)}', style: context.text.labelSmall?.copyWith(color: context.palette.muted)),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
