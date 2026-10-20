import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/backend/message_backend.dart' show MessageAttachment;
import '../../../models/models.dart';
import '../../../providers/core_providers.dart';
import '../../../providers/message_providers.dart';
import '../../../services/file_service.dart';
import '../../../widgets/common.dart';
import '../../../widgets/document_viewer.dart';
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

/// Opens an applicant's CV or cover letter in the in-app viewer.
Future<void> openDocument(BuildContext context, WidgetRef ref, String? storagePath, {required String fileName, DocumentFormat? format, String title = 'CV'}) =>
    viewDocument(
      context,
      title: title,
      fileName: fileName,
      format: format,
      storagePath: storagePath,
      loadUrl: ref.read(employerBackendProvider).documentUrl,
    );

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
  int _sortColumn = 3;
  bool _matchOnly = false;
  final Set<String> _selected = {};
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

  /// Moves several candidates to one stage and sends each the same message.
  Future<void> _bulk(List<JobApplication> apps) async {
    if (apps.isEmpty) return;
    final company = ref.read(companyProvider).value?.data?.name ?? 'our company';
    final result = await showDialog<(ApplicationStatus, String, PickedFile?)>(context: context, builder: (_) => _BulkDialog(count: apps.length, company: company));
    if (result == null || !mounted) return;
    final (status, template, file) = result;
    final messages = ref.read(messageBackendProvider);
    // Upload once; every candidate's message points to the same file.
    MessageAttachment? attachment;
    if (file != null) {
      try {
        attachment = await messages.uploadAttachment(file.name, file.bytes);
      } catch (e) {
        if (mounted) showError(context, e);
        return;
      }
    }
    var done = 0;
    for (final a in apps) {
      try {
        final text = fillTemplate(template, name: a.applicant.fullName, job: a.job?.title ?? 'the job', company: company);
        await ref.read(candidatesProvider.notifier).updateCandidate(a, status: status == a.status ? null : status, message: text.trim().isEmpty ? null : text);
        if (attachment != null) {
          // Same text as the stage message, so the thread shows it once, with the file.
          await messages.send(a.id, text, asEmployer: true, attachment: attachment);
          ref.invalidate(messageThreadProvider(a.id));
        }
        done++;
      } catch (_) {
        // Keep going; the count below shows how many worked.
      }
    }
    if (!mounted) return;
    setState(_selected.clear);
    final what = attachment == null ? 'messaged' : 'sent ${attachment.name}';
    showSnack(context, done == apps.length ? '$done candidates moved to ${status.label} and $what' : '$done of ${apps.length} updated. Try the rest again.');
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(candidatesProvider);
    final unread = ref.watch(unreadRepliesProvider).value ?? const <String, int>{};
    final jobs = ref.watch(employerJobsProvider).value?.data ?? const <Job>[];
    final all = async.value?.data ?? const <JobApplication>[];
    final q = _query.trim().toLowerCase();

    var list = all.where((a) {
      if (_jobId != null && a.jobId != _jobId) return false;
      if (_status != null && a.status != _status) return false;
      if (_matchOnly) {
        final m = a.screeningMatch(null);
        if (m.total == 0 || m.matched < m.total) return false;
      }
      if (q.isNotEmpty && !('${a.applicant.fullName} ${a.applicant.email} ${a.job?.title ?? ''}'.toLowerCase().contains(q))) return false;
      return true;
    }).toList();
    int cmp(JobApplication a, JobApplication b) => switch (_sortColumn) {
          1 => a.applicant.fullName.toLowerCase().compareTo(b.applicant.fullName.toLowerCase()),
          2 => (a.job?.title ?? '').compareTo(b.job?.title ?? ''),
          4 => ApplicationStatus.values.indexOf(a.status).compareTo(ApplicationStatus.values.indexOf(b.status)),
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
          if (jobs.any((j) => j.screening.any((q) => q.wanted != null)))
            FilterChip(
              label: const Text('Meets all screening answers'),
              selected: _matchOnly,
              onSelected: (v) => setState(() => _matchOnly = v),
            ),
          Text('${list.length} of ${all.length}', style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
        ]),
        if (_selected.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: context.colors.primaryContainer, borderRadius: BorderRadius.circular(AppSpacing.radius)),
            child: Wrap(spacing: 10, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text('${_selected.length} selected', style: context.text.titleSmall),
              FilledButton.icon(
                onPressed: () => _bulk(all.where((a) => _selected.contains(a.id)).toList()),
                icon: const Icon(Icons.send_rounded, size: 18),
                label: const Text('Move and message'),
              ),
              TextButton(onPressed: () => setState(_selected.clear), child: const Text('Clear')),
            ]),
          ),
        ],
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
              DataColumn(
                label: Checkbox(
                  value: list.isNotEmpty && list.every((a) => _selected.contains(a.id)),
                  onChanged: (v) => setState(() => v == true ? _selected.addAll(list.where((a) => a.status != ApplicationStatus.withdrawn).map((a) => a.id)) : _selected.clear()),
                ),
              ),
              DataColumn(label: const Text('Candidate'), onSort: sortBy),
              DataColumn(label: const Text('Job'), onSort: sortBy),
              DataColumn(label: const Text('Applied'), onSort: sortBy),
              DataColumn(label: const Text('Stage'), onSort: sortBy),
              const DataColumn(label: Text('Screening')),
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
                  onSelectChanged: (_) => context.push('/employer/candidates/${a.id}'),
                  cells: [
                    DataCell(Checkbox(
                      value: _selected.contains(a.id),
                      onChanged: a.status == ApplicationStatus.withdrawn
                          ? null
                          : (v) => setState(() => v == true ? _selected.add(a.id) : _selected.remove(a.id)),
                    )),
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
                    DataCell(Builder(builder: (_) {
                      final m = a.screeningMatch(null);
                      if (m.total == 0) return const Text('—');
                      final all = m.matched == m.total;
                      return Text('${m.matched}/${m.total}${all ? ' ✓' : ''}',
                          style: TextStyle(color: all ? AppColors.green : AppColors.warning, fontWeight: FontWeight.w700));
                    })),
                    DataCell(Text(a.interviewAt == null ? '—' : Fmt.dateTime(a.interviewAt!))),
                    DataCell(IconButton(
                      tooltip: 'Open CV: ${a.resume.fileName}',
                      icon: const Icon(Icons.description_outlined),
                      onPressed: () => openDocument(context, ref, a.resume.storagePath, fileName: a.resume.fileName, format: a.resume.format, title: '${a.applicant.fullName} · CV'),
                    )),
                    DataCell((unread[a.id] ?? 0) > 0
                        ? Tooltip(
                            message: '${unread[a.id]} new ${unread[a.id] == 1 ? 'reply' : 'replies'}',
                            child: Badge(label: Text('${unread[a.id]}'), child: const Icon(Icons.chat_bubble_outline_rounded)),
                          )
                        : const Icon(Icons.chevron_right_rounded)),
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

/// Ready-made messages for each stage. {name}, {job} and {company} are filled in per candidate.
const messageTemplates = <ApplicationStatus, String>{
  ApplicationStatus.shortlisted: 'Dear {name},\n\nThank you for applying for {job}. We are pleased to tell you that you have been shortlisted. We will contact you soon about the next step.\n\nKind regards,\n{company}',
  ApplicationStatus.assessment: 'Dear {name},\n\nThank you for your interest in {job}. As the next step, we would like you to complete a short assessment. We will send you the details shortly.\n\nKind regards,\n{company}',
  ApplicationStatus.interview: 'Dear {name},\n\nWe would like to invite you to an interview for {job}. Please reply to confirm you are available, and we will send you the date, time and place.\n\nKind regards,\n{company}',
  ApplicationStatus.offer: 'Dear {name},\n\nWe are delighted to offer you the position of {job}. We will be in touch with the details of the offer.\n\nKind regards,\n{company}',
  ApplicationStatus.hired: 'Dear {name},\n\nWelcome to {company}! We look forward to working with you as {job}.\n\nKind regards,\n{company}',
  ApplicationStatus.rejected: 'Dear {name},\n\nThank you for your interest in {job} and for the time you took to apply. After careful consideration, we have decided not to move forward with your application this time. We wish you every success in your job search.\n\nKind regards,\n{company}',
};

String fillTemplate(String template, {required String name, required String job, required String company}) => template
    .replaceAll('{name}', name.trim().isEmpty ? 'Applicant' : name.trim().split(RegExp(r'\s+')).first)
    .replaceAll('{job}', job)
    .replaceAll('{company}', company);

class _BulkDialog extends ConsumerStatefulWidget {
  const _BulkDialog({required this.count, required this.company});
  final int count;
  final String company;

  @override
  ConsumerState<_BulkDialog> createState() => _BulkDialogState();
}

class _BulkDialogState extends ConsumerState<_BulkDialog> {
  ApplicationStatus _status = ApplicationStatus.shortlisted;
  PickedFile? _file;

  Future<void> _pickPdf() async {
    try {
      final f = await ref.read(fileServiceProvider).pickDocument();
      if (f != null) setState(() => _file = f);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }
  late final _message = TextEditingController(text: messageTemplates[_status]);

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Update ${widget.count} candidate${widget.count == 1 ? '' : 's'}'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<ApplicationStatus>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Move to stage'),
                items: [
                  for (final s in employerStatuses.where((s) => s != ApplicationStatus.applied && s != ApplicationStatus.viewed))
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: (v) => setState(() {
                  _status = v ?? _status;
                  _message.text = messageTemplates[_status] ?? '';
                }),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _message,
                minLines: 6,
                maxLines: 12,
                decoration: const InputDecoration(labelText: 'Message (sent to each candidate)', alignLabelWithHint: true),
              ),
              const SizedBox(height: 6),
              Text('{name} becomes each candidate\'s first name; {job} the job title. Leave empty to change the stage without a message.',
                  style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
              const SizedBox(height: 12),
              if (_file == null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _pickPdf,
                    icon: const Icon(Icons.attach_file_rounded, size: 18),
                    label: const Text('Attach a PDF (e.g. offer letter)'),
                  ),
                )
              else
                Align(
                  alignment: Alignment.centerLeft,
                  child: InputChip(
                    avatar: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.danger, size: 18),
                    label: Text(_file!.name, overflow: TextOverflow.ellipsis),
                    onDeleted: () => setState(() => _file = null),
                    deleteButtonTooltipMessage: 'Remove file',
                  ),
                ),
              if (_file != null) ...[
                const SizedBox(height: 6),
                Text('Every selected candidate gets the same file. For personal offer letters, send each one from the candidate\'s page.',
                    style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, (_status, _message.text, _file)),
            style: _status == ApplicationStatus.rejected ? FilledButton.styleFrom(backgroundColor: AppColors.danger) : null,
            child: Text(_status == ApplicationStatus.rejected ? 'Reject and send' : 'Update and send'),
          ),
        ],
      );
}
