import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/models.dart';
import '../../../widgets/common.dart';
import '../../../widgets/skeletons.dart';
import '../../../widgets/states.dart';
import '../../providers.dart';
import '../../widgets.dart';
import '../company/company_screens.dart';

enum _JobFilter {
  all('All'),
  live('Live'),
  pending('Awaiting approval'),
  needsChanges('Needs changes'),
  draft('Drafts'),
  closed('Closed');

  const _JobFilter(this.label);
  final String label;

  bool matches(Job j) => switch (this) {
    _JobFilter.all => true,
    _JobFilter.live => j.status == JobStatus.published,
    _JobFilter.pending => j.status == JobStatus.pending,
    _JobFilter.needsChanges => j.status == JobStatus.declined || j.status == JobStatus.rejected,
    _JobFilter.draft => j.status == JobStatus.draft,
    _JobFilter.closed => j.status == JobStatus.closed,
  };
}

class MyJobsScreen extends ConsumerStatefulWidget {
  const MyJobsScreen({super.key});

  @override
  ConsumerState<MyJobsScreen> createState() => _MyJobsScreenState();
}

class _MyJobsScreenState extends ConsumerState<MyJobsScreen> {
  _JobFilter _filter = _JobFilter.all;
  String _query = '';

  Future<void> _act(Job job, String action) async {
    final ctrl = ref.read(employerJobsProvider.notifier);
    try {
      switch (action) {
        case 'edit':
          context.push('/employer/jobs/${job.id}/edit');
        case 'applicants':
          context.go('/employer/candidates?job=${job.id}');
        case 'preview':
          context.push('/employer/jobs/${job.id}/edit?preview=1');
        case 'close':
          if (await confirmDialog(
            context,
            title: 'Close this job?',
            message: 'It will stop accepting applications. Existing applicants stay in your pipeline.',
            confirmLabel: 'Close job',
          )) {
            await ctrl.setStatus(job, JobStatus.closed);
            if (mounted) showSnack(context, 'Job closed');
          }
        case 'reopen':
          await ctrl.setStatus(job, JobStatus.published);
          if (mounted) showSnack(context, 'Job reopened');
        case 'delete':
          if (await confirmDialog(context, title: 'Delete this job?', message: '"${job.title}" will be deleted.', confirmLabel: 'Delete', destructive: true)) {
            await ctrl.deleteDraft(job);
            if (mounted) showSnack(context, 'Job deleted');
          }
      }
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(companyProvider).value?.data;
    final async = ref.watch(employerJobsProvider);
    final all = async.value?.data ?? const <Job>[];
    final q = _query.trim().toLowerCase();
    final jobs = all.where((j) => _filter.matches(j) && (q.isEmpty || j.title.toLowerCase().contains(q) || j.location.toLowerCase().contains(q))).toList();

    return EmployerPage(
      title: 'My jobs',
      subtitle: '${all.where((j) => j.status == JobStatus.published).length} live · ${all.length} total',
      onRefresh: () => ref.read(employerJobsProvider.notifier).refresh(),
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
        if (async.value?.isOfflineCopy ?? false) CacheNotice(syncedAt: async.value?.syncedAt, onRetry: () => ref.read(employerJobsProvider.notifier).refresh()),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final f in _JobFilter.values)
              ChoiceChip(label: Text('${f.label} (${all.where(f.matches).length})'), selected: _filter == f, onSelected: (_) => setState(() => _filter = f)),
            SizedBox(
              width: 260,
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(hintText: 'Search jobs', prefixIcon: Icon(Icons.search_rounded), isDense: true),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (async.isLoading && !async.hasValue)
          const Skeleton(child: Column(children: [ListTileSkeleton(trailing: true), ListTileSkeleton(trailing: true), ListTileSkeleton(trailing: true)]))
        else if (async.hasError && !async.hasValue)
          ErrorState(error: async.error!, onRetry: () => ref.invalidate(employerJobsProvider))
        else
          TableCard(
            empty: EmptyState(
              icon: Icons.work_outline_rounded,
              title: all.isEmpty ? 'Post your first job' : 'No jobs match',
              message: all.isEmpty ? 'Create a listing and start receiving applications from candidates across Sierra Leone.' : 'Try another filter or search.',
              action: all.isEmpty ? 'Post a job' : null,
              onAction: () => context.push('/employer/jobs/new'),
            ),
            columns: const [
              DataColumn(label: Text('Job')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Applicants'), numeric: true),
              DataColumn(label: Text('Views'), numeric: true),
              DataColumn(label: Text('Posted')),
              DataColumn(label: Text('Deadline')),
              DataColumn(label: Text('')),
            ],
            rows: [
              for (final j in jobs)
                DataRow(
                  onSelectChanged: (_) => _act(j, const {JobStatus.draft, JobStatus.declined, JobStatus.rejected}.contains(j.status) ? 'edit' : 'applicants'),
                  cells: [
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 280),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              j.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            if (j.reviewNote.isNotEmpty && (j.status == JobStatus.declined || j.status == JobStatus.rejected))
                              Text(
                                j.reviewNote,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.bodySmall?.copyWith(color: AppColors.warning),
                              )
                            else
                              Text(
                                '${j.location} · ${j.employmentType.label}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: context.text.bodySmall?.copyWith(color: context.palette.muted),
                              ),
                          ],
                        ),
                      ),
                    ),
                    DataCell(JobStatusPill(j.status)),
                    DataCell(Text('${j.applicants}')),
                    DataCell(Text('${j.views}')),
                    DataCell(Text(j.status == JobStatus.draft ? '—' : Fmt.dateShort(j.postedAt))),
                    DataCell(
                      Text(
                        Fmt.deadline(j.deadline),
                        style: TextStyle(color: j.isClosed ? AppColors.danger : (Fmt.deadlineSoon(j.deadline) ? AppColors.warning : null)),
                      ),
                    ),
                    DataCell(
                      PopupMenuButton<String>(
                        tooltip: 'Actions for ${j.title}',
                        onSelected: (a) => _act(j, a),
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'edit',
                            child: Text(
                              j.status == JobStatus.declined
                                  ? 'Edit and resubmit'
                                  : j.status == JobStatus.rejected
                                  ? 'View'
                                  : 'Edit',
                            ),
                          ),
                          if (j.status != JobStatus.draft) const PopupMenuItem(value: 'applicants', child: Text('View applicants')),
                          if (j.status == JobStatus.published) const PopupMenuItem(value: 'close', child: Text('Close job')),
                          if (j.status == JobStatus.closed) const PopupMenuItem(value: 'reopen', child: Text('Reopen')),
                          if (const {JobStatus.draft, JobStatus.declined, JobStatus.rejected}.contains(j.status))
                            const PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                    ),
                  ],
                ),
            ],
          ),
      ],
    );
  }
}
