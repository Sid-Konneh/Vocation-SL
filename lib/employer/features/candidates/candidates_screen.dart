import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/models.dart';
import '../../../widgets/common.dart';
import '../../../widgets/skeletons.dart';
import '../../../widgets/states.dart';
import '../../providers.dart';
import '../../widgets.dart';

/// Statuses an employer can set (withdrawn is the candidate's choice only).
const employerStatuses = [
  ApplicationStatus.applied,
  ApplicationStatus.viewed,
  ApplicationStatus.shortlisted,
  ApplicationStatus.assessment,
  ApplicationStatus.interview,
  ApplicationStatus.offer,
  ApplicationStatus.hired,
  ApplicationStatus.rejected,
];

Future<void> openDocument(BuildContext context, WidgetRef ref, String? storagePath) async {
  if (storagePath == null || storagePath.isEmpty) {
    showSnack(context, 'This file was attached in demo mode and has no download.', error: true);
    return;
  }
  try {
    final url = await ref.read(employerBackendProvider).documentUrl(storagePath);
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) showSnack(context, 'Couldn\'t open the file.', error: true);
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

class CandidatesScreen extends ConsumerStatefulWidget {
  const CandidatesScreen({super.key, this.jobId});
  final String? jobId;

  @override
  ConsumerState<CandidatesScreen> createState() => _CandidatesScreenState();
}

class _CandidatesScreenState extends ConsumerState<CandidatesScreen> {
  late String? _jobId = widget.jobId;
  ApplicationStatus? _status;
  String _query = '';
  int _sortColumn = 2;
  bool _ascending = false;

  @override
  void didUpdateWidget(CandidatesScreen old) {
    super.didUpdateWidget(old);
    if (widget.jobId != old.jobId) _jobId = widget.jobId;
  }

  Future<void> _setStatus(JobApplication a, ApplicationStatus s) async {
    if (s == a.status) return;
    if (s == ApplicationStatus.rejected &&
        !await confirmDialog(context,
            title: 'Reject ${a.applicant.fullName}?',
            message: 'They will be notified that they were not selected for ${a.job?.title ?? 'this job'}.',
            confirmLabel: 'Reject',
            destructive: true)) {
      return;
    }
    try {
      await ref.read(candidatesProvider.notifier).updateCandidate(a, status: s);
      if (mounted) showSnack(context, '${a.applicant.fullName} moved to ${s.label}');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(candidatesProvider);
    final jobs = ref.watch(employerJobsProvider).value?.data ?? const <Job>[];
    final all = async.value?.data ?? const <JobApplication>[];
    final q = _query.trim().toLowerCase();

    var list = all.where((a) {
      if (_jobId != null && a.jobId != _jobId) return false;
      if (_status != null && a.status != _status) return false;
      if (q.isNotEmpty && !('${a.applicant.fullName} ${a.applicant.email} ${a.job?.title ?? ''}'.toLowerCase().contains(q))) return false;
      return true;
    }).toList();
    int cmp(JobApplication a, JobApplication b) => switch (_sortColumn) {
          0 => a.applicant.fullName.toLowerCase().compareTo(b.applicant.fullName.toLowerCase()),
          1 => (a.job?.title ?? '').compareTo(b.job?.title ?? ''),
          3 => ApplicationStatus.values.indexOf(a.status).compareTo(ApplicationStatus.values.indexOf(b.status)),
          _ => a.submittedAt.compareTo(b.submittedAt),
        };
    list.sort((a, b) => _ascending ? cmp(a, b) : cmp(b, a));

    void sortBy(int i, bool asc) => setState(() {
          _sortColumn = i;
          _ascending = asc;
        });

    return EmployerPage(
      title: 'Candidates',
      subtitle: 'Your applicant tracking system: every application to your jobs.',
      onRefresh: () => ref.read(candidatesProvider.notifier).refresh(),
      children: [
        if (async.value?.isOfflineCopy ?? false)
          CacheNotice(syncedAt: async.value?.syncedAt, onRetry: () => ref.read(candidatesProvider.notifier).refresh()),
        Wrap(spacing: 12, runSpacing: 12, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 280,
            child: DropdownButtonFormField<String?>(
              initialValue: jobs.any((j) => j.id == _jobId) ? _jobId : null,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Job', isDense: true),
              items: [
                const DropdownMenuItem(value: null, child: Text('All jobs')),
                for (final j in jobs.where((j) => j.status != JobStatus.draft))
                  DropdownMenuItem(value: j.id, child: Text(j.title, overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _jobId = v),
            ),
          ),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<ApplicationStatus?>(
              initialValue: _status,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Stage', isDense: true),
              items: [
                const DropdownMenuItem(value: null, child: Text('All stages')),
                for (final s in [...employerStatuses, ApplicationStatus.withdrawn])
                  DropdownMenuItem(value: s, child: Text('${s.label} (${all.where((a) => a.status == s && (_jobId == null || a.jobId == _jobId)).length})')),
              ],
              onChanged: (v) => setState(() => _status = v),
            ),
          ),
          SizedBox(
            width: 260,
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(hintText: 'Search name or email', prefixIcon: Icon(Icons.search_rounded), isDense: true),
            ),
          ),
          Text('${list.length} of ${all.length}', style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
        ]),
        const SizedBox(height: 16),
        if (async.isLoading && !async.hasValue)
          const Skeleton(child: Column(children: [ListTileSkeleton(trailing: true), ListTileSkeleton(trailing: true), ListTileSkeleton(trailing: true)]))
        else if (async.hasError && !async.hasValue)
          ErrorState(error: async.error!, onRetry: () => ref.invalidate(candidatesProvider))
        else
          TableCard(
            sortColumnIndex: _sortColumn,
            sortAscending: _ascending,
            empty: EmptyState(
              icon: Icons.people_outline_rounded,
              title: all.isEmpty ? 'No applicants yet' : 'No candidates match',
              message: all.isEmpty ? 'When candidates apply to your jobs, they appear here.' : 'Try another job, stage or search.',
            ),
            columns: [
              DataColumn(label: const Text('Candidate'), onSort: sortBy),
              DataColumn(label: const Text('Job'), onSort: sortBy),
              DataColumn(label: const Text('Applied'), onSort: sortBy),
              DataColumn(label: const Text('Stage'), onSort: sortBy),
              const DataColumn(label: Text('Interview')),
              const DataColumn(label: Text('CV')),
              const DataColumn(label: Text('')),
            ],
            rows: [
              for (final a in list)
                DataRow(
                  color: a.status == ApplicationStatus.applied
                      ? WidgetStatePropertyAll(context.palette.accentTint.withValues(alpha: 0.5))
                      : null,
                  onSelectChanged: (_) => context.push('/candidates/${a.id}'),
                  cells: [
                    DataCell(ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: Row(children: [
                        UserAvatar(initials: _initials(a.applicant.fullName), size: 34),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(a.applicant.fullName,
                                maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall?.copyWith(fontWeight: a.status == ApplicationStatus.applied ? FontWeight.w800 : FontWeight.w600)),
                            Text(a.applicant.email, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
                          ]),
                        ),
                      ]),
                    )),
                    DataCell(ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(a.job?.title ?? '—', maxLines: 2, overflow: TextOverflow.ellipsis),
                    )),
                    DataCell(Text(Fmt.dateShort(a.submittedAt))),
                    DataCell(a.status == ApplicationStatus.withdrawn
                        ? const StatusChip(ApplicationStatus.withdrawn, dense: true)
                        : DropdownButtonHideUnderline(
                            child: DropdownButton<ApplicationStatus>(
                              value: a.status,
                              isDense: true,
                              borderRadius: BorderRadius.circular(12),
                              items: [for (final s in employerStatuses) DropdownMenuItem(value: s, child: StatusChip(s, dense: true))],
                              onChanged: (s) => s == null ? null : _setStatus(a, s),
                            ),
                          )),
                    DataCell(Text(a.interviewAt == null ? '—' : Fmt.dateTime(a.interviewAt!))),
                    DataCell(IconButton(
                      tooltip: 'Open CV: ${a.resume.fileName}',
                      icon: const Icon(Icons.description_outlined),
                      onPressed: () => openDocument(context, ref, a.resume.storagePath),
                    )),
                    DataCell(const Icon(Icons.chevron_right_rounded)),
                  ],
                ),
            ],
          ),
        const SizedBox(height: 8),
        Text('Unreviewed applications are highlighted. Changing a stage notifies the candidate.',
            style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
      ],
    );
  }
}

String _initials(String name) {
  final p = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (p.isEmpty) return '?';
  return p.length > 1 ? '${p.first[0]}${p.last[0]}'.toUpperCase() : p.first[0].toUpperCase();
}
