import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../employer/widgets.dart';
import '../../models/models.dart';
import '../../widgets/common.dart';
import '../../widgets/company_logo.dart';
import '../../widgets/states.dart';
import '../admin_providers.dart';
import '../admin_shell.dart';

Future<void> _act(BuildContext context, WidgetRef ref, String done, Future<void> Function() action) async {
  try {
    await action();
    if (context.mounted) showSnack(context, done);
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

Widget _search(String hint, ValueChanged<String> onChanged) => SizedBox(
      width: 280,
      child: TextField(onChanged: onChanged, decoration: InputDecoration(hintText: hint, prefixIcon: const Icon(Icons.search_rounded), isDense: true)),
    );

// ---- Job moderation ------------------------------------------------------------------

class AdminJobsScreen extends ConsumerStatefulWidget {
  const AdminJobsScreen({super.key});

  @override
  ConsumerState<AdminJobsScreen> createState() => _AdminJobsScreenState();
}

class _AdminJobsScreenState extends ConsumerState<AdminJobsScreen> {
  JobStatus? _status = JobStatus.pending;
  String _q = '';

  Future<void> _do(Job j, String action) async {
    final a = ref.read(adminActionsProvider);
    final refresh = [adminJobsProvider, adminInvoicesProvider];
    switch (action) {
      case 'approve':
        await _act(context, ref, '"${j.title}" approved and live. Its invoice is in Invoices.',
            () => a.run((b) => b.setJobStatus(j.id, JobStatus.published), refresh: refresh));
      case 'decline' || 'reject':
        final status = action == 'decline' ? JobStatus.declined : JobStatus.rejected;
        final note = await showDialog<String>(context: context, builder: (_) => _JobReviewDialog(job: j, status: status));
        if (note == null || !mounted) return;
        await _act(context, ref, action == 'decline' ? '"${j.title}" sent back to the employer' : '"${j.title}" rejected',
            () => a.run((b) => b.setJobStatus(j.id, status, note: note), refresh: refresh));
      case 'close':
        if (await confirmDialog(context, title: 'Take this job down?', message: '"${j.title}" will stop showing to job seekers.', confirmLabel: 'Close job')) {
          if (!mounted) return;
          await _act(context, ref, 'Job closed', () => a.run((b) => b.setJobStatus(j.id, JobStatus.closed), refresh: refresh));
        }
      case 'reopen':
        await _act(context, ref, 'Job reopened', () => a.run((b) => b.setJobStatus(j.id, JobStatus.published), refresh: refresh));
      case 'feature':
        await _act(context, ref, j.featured ? 'Removed from featured' : 'Featured on the home screen',
            () => a.run((b) => b.setJobFeatured(j.id, !j.featured), refresh: refresh));
      case 'delete':
        if (await confirmDialog(context, title: 'Delete "${j.title}"?', message: 'The job and its applications are removed permanently.', confirmLabel: 'Delete', destructive: true)) {
          if (!mounted) return;
          await _act(context, ref, 'Job deleted', () => a.run((b) => b.deleteJob(j.id), refresh: refresh));
        }
      case 'view':
        await showDialog<void>(context: context, builder: (_) => _JobDialog(job: j));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminJobsProvider);
    final canModerate = adminCan(ref, AdminRole.moderator);
    return EmployerPage(
      title: 'Job moderation',
      subtitle: 'Review new jobs, take down problem listings and choose featured jobs.',
      onRefresh: () async => ref.invalidate(adminJobsProvider),
      children: [
        AdminAsync<List<Job>>(
          value: async,
          onRetry: () => ref.invalidate(adminJobsProvider),
          builder: (all) {
            final q = _q.trim().toLowerCase();
            final jobs = all
                .where((j) => (_status == null || j.status == _status) &&
                    (q.isEmpty || '${j.title} ${j.companyName} ${j.location}'.toLowerCase().contains(q)))
                .toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final s in [null, ...JobStatus.values])
                  ChoiceChip(
                    label: Text('${s?.label ?? 'All'} (${all.where((j) => s == null || j.status == s).length})'),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = s),
                  ),
                _search('Search title, company or town', (v) => setState(() => _q = v)),
              ]),
              const SizedBox(height: 16),
              TableCard(
                empty: EmptyState(
                  icon: Icons.task_alt_rounded,
                  title: _status == JobStatus.pending ? 'Nothing to review' : 'No jobs match',
                  message: _status == JobStatus.pending ? 'New and resubmitted jobs appear here for approval.' : 'Try another filter.',
                ),
                columns: const [
                  DataColumn(label: Text('Job')),
                  DataColumn(label: Text('Company')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Posted')),
                  DataColumn(label: Text('Applicants'), numeric: true),
                  DataColumn(label: Text('Views'), numeric: true),
                  DataColumn(label: Text('')),
                ],
                rows: [
                  for (final j in jobs)
                    DataRow(onSelectChanged: (_) => _do(j, 'view'), cells: [
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: Row(children: [
                          if (j.featured) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.star_rounded, size: 16, color: AppColors.warning)),
                          Flexible(child: Text(j.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                        ]),
                      )),
                      DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 200), child: Text(j.companyName, maxLines: 1, overflow: TextOverflow.ellipsis))),
                      DataCell(JobStatusPill(j.status)),
                      DataCell(Text(Fmt.dateShort(j.postedAt))),
                      DataCell(Text('${j.applicants}')),
                      DataCell(Text('${j.views}')),
                      DataCell(PopupMenuButton<String>(
                        tooltip: 'Moderate ${j.title}',
                        enabled: canModerate,
                        onSelected: (a) => _do(j, a),
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'view', child: Text('View details')),
                          if (j.status == JobStatus.pending || j.status == JobStatus.declined)
                            const PopupMenuItem(value: 'approve', child: Text('Approve and publish')),
                          if (j.status == JobStatus.pending) const PopupMenuItem(value: 'decline', child: Text('Decline (send back for changes)')),
                          if (j.status == JobStatus.pending || j.status == JobStatus.declined) const PopupMenuItem(value: 'reject', child: Text('Reject')),
                          if (j.status == JobStatus.published) const PopupMenuItem(value: 'close', child: Text('Take down (close)')),
                          if (j.status == JobStatus.closed) const PopupMenuItem(value: 'reopen', child: Text('Reopen')),
                          if (j.status == JobStatus.published) PopupMenuItem(value: 'feature', child: Text(j.featured ? 'Remove from featured' : 'Feature on home screen')),
                          const PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      )),
                    ]),
                ],
              ),
            ]);
          },
        ),
      ],
    );
  }
}

class _JobDialog extends StatelessWidget {
  const _JobDialog({required this.job});
  final Job job;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(job.title),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text('${job.companyName} · ${job.location} · ${job.employmentType.label} · ${Fmt.salary(job)}', style: context.text.bodyMedium),
              const SizedBox(height: 8),
              Wrap(spacing: 8, children: [JobStatusPill(job.status), TagChip('Closes ${Fmt.date(job.deadline)}', dense: true)]),
              if (job.reviewNote.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Review note: ${job.reviewNote}', style: context.text.bodySmall),
              ],
              const SizedBox(height: 16),
              Text(job.about, style: context.text.titleSmall),
              const SizedBox(height: 8),
              Text(job.description, style: context.text.bodyMedium),
              if (job.requirements.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Requirements', style: context.text.labelLarge),
                BulletList(job.requirements),
              ],
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      );
}

/// Asks for the reason shown to the employer when declining or rejecting a job.
class _JobReviewDialog extends StatefulWidget {
  const _JobReviewDialog({required this.job, required this.status});
  final Job job;
  final JobStatus status;

  @override
  State<_JobReviewDialog> createState() => _JobReviewDialogState();
}

class _JobReviewDialogState extends State<_JobReviewDialog> {
  final _c = TextEditingController();
  String? _error;

  bool get _decline => widget.status == JobStatus.declined;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_decline ? 'Decline "${widget.job.title}"?' : 'Reject "${widget.job.title}"?'),
        content: SizedBox(
          width: 480,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_decline
                ? 'The employer sees your note, can edit the job and send it back for review.'
                : 'Rejection is final: the job can\'t be resubmitted. Use Decline if the employer can fix it.'),
            const SizedBox(height: 12),
            TextField(
              controller: _c,
              minLines: 2,
              maxLines: 5,
              decoration: InputDecoration(
                labelText: _decline ? 'What needs to change? (shown to the employer)' : 'Reason (shown to the employer)',
                errorText: _error,
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (_c.text.trim().isEmpty) {
                setState(() => _error = 'Tell the employer why');
                return;
              }
              Navigator.pop(context, _c.text.trim());
            },
            style: FilledButton.styleFrom(backgroundColor: _decline ? null : AppColors.danger, minimumSize: const Size(64, 44)),
            child: Text(_decline ? 'Decline' : 'Reject'),
          ),
        ],
      );
}

// ---- Employer verification -------------------------------------------------------------

class AdminEmployersScreen extends ConsumerStatefulWidget {
  const AdminEmployersScreen({super.key});

  @override
  ConsumerState<AdminEmployersScreen> createState() => _AdminEmployersScreenState();
}

class _AdminEmployersScreenState extends ConsumerState<AdminEmployersScreen> {
  CompanyStatus? _status = CompanyStatus.pending;
  String _q = '';

  Future<void> _do(AdminCompany c, String action) async {
    final a = ref.read(adminActionsProvider);
    final refresh = [adminCompaniesProvider, adminJobsProvider, adminInvoicesProvider];
    final name = c.company.name;
    switch (action) {
      case 'approve':
        await _act(context, ref, '$name approved and given the verified check mark',
            () => a.run((b) => b.setCompanyStatus(c.company.id, CompanyStatus.approved), refresh: refresh));
      case 'reject':
        if (await confirmDialog(context, title: 'Reject $name?', message: 'Their jobs stay hidden. They can contact support to appeal.', confirmLabel: 'Reject', destructive: true)) {
          if (!mounted) return;
          await _act(context, ref, '$name rejected', () => a.run((b) => b.setCompanyStatus(c.company.id, CompanyStatus.rejected), refresh: refresh));
        }
      case 'suspend':
        if (await confirmDialog(context, title: 'Suspend $name?', message: 'Their jobs are hidden from job seekers until reinstated.', confirmLabel: 'Suspend', destructive: true)) {
          if (!mounted) return;
          await _act(context, ref, '$name suspended', () => a.run((b) => b.setCompanyStatus(c.company.id, CompanyStatus.suspended), refresh: refresh));
        }
      case 'reinstate':
        await _act(context, ref, '$name reinstated', () => a.run((b) => b.setCompanyStatus(c.company.id, CompanyStatus.approved), refresh: refresh));
      case 'verify':
        await _act(context, ref, c.company.verified ? 'Verified badge removed' : 'Verified badge added',
            () => a.run((b) => b.setCompanyVerified(c.company.id, !c.company.verified), refresh: refresh));
      case 'view':
        await showDialog<void>(context: context, builder: (_) => _CompanyDialog(c: c));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminCompaniesProvider);
    final canModerate = adminCan(ref, AdminRole.moderator);
    return EmployerPage(
      title: 'Employer verification',
      subtitle: 'Approve new companies before their jobs go live, and manage verified badges.',
      onRefresh: () async => ref.invalidate(adminCompaniesProvider),
      children: [
        AdminAsync<List<AdminCompany>>(
          value: async,
          onRetry: () => ref.invalidate(adminCompaniesProvider),
          builder: (all) {
            final q = _q.trim().toLowerCase();
            final list = all
                .where((c) => (_status == null || c.company.status == _status) &&
                    (q.isEmpty || '${c.company.name} ${c.company.email} ${c.company.location}'.toLowerCase().contains(q)))
                .toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                for (final s in [null, ...CompanyStatus.values])
                  ChoiceChip(
                    label: Text('${s?.label ?? 'All'} (${all.where((c) => s == null || c.company.status == s).length})'),
                    selected: _status == s,
                    onSelected: (_) => setState(() => _status = s),
                  ),
                _search('Search name, email or town', (v) => setState(() => _q = v)),
              ]),
              const SizedBox(height: 16),
              TableCard(
                empty: EmptyState(
                  icon: Icons.verified_user_outlined,
                  title: _status == CompanyStatus.pending ? 'No companies waiting' : 'No companies match',
                  message: _status == CompanyStatus.pending ? 'New employer sign-ups appear here for review.' : 'Try another filter.',
                ),
                columns: const [
                  DataColumn(label: Text('Company')),
                  DataColumn(label: Text('Contact')),
                  DataColumn(label: Text('Status')),
                  DataColumn(label: Text('Jobs'), numeric: true),
                  DataColumn(label: Text('Team'), numeric: true),
                  DataColumn(label: Text('Joined')),
                  DataColumn(label: Text('')),
                ],
                rows: [
                  for (final c in list)
                    DataRow(onSelectChanged: (_) => _do(c, 'view'), cells: [
                      DataCell(ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 260),
                        child: Row(children: [
                          CompanyLogo(company: c.company, size: 32),
                          const SizedBox(width: 10),
                          Flexible(child: Text(c.company.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700))),
                          if (c.company.verified) Padding(padding: const EdgeInsets.only(left: 4), child: Icon(Icons.verified_rounded, size: 16, color: context.colors.primary)),
                        ]),
                      )),
                      DataCell(Text(c.company.email.isEmpty ? '—' : c.company.email)),
                      DataCell(_CompanyStatusPill(c.company.status)),
                      DataCell(Text('${c.jobCount}')),
                      DataCell(Text('${c.members}')),
                      DataCell(Text(Fmt.dateShort(c.createdAt))),
                      DataCell(PopupMenuButton<String>(
                        tooltip: 'Actions for ${c.company.name}',
                        enabled: canModerate,
                        onSelected: (a) => _do(c, a),
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'view', child: Text('View details')),
                          if (c.company.status == CompanyStatus.pending || c.company.status == CompanyStatus.rejected)
                            const PopupMenuItem(value: 'approve', child: Text('Approve')),
                          if (c.company.status == CompanyStatus.pending) const PopupMenuItem(value: 'reject', child: Text('Reject')),
                          if (c.company.status == CompanyStatus.approved) const PopupMenuItem(value: 'suspend', child: Text('Suspend')),
                          if (c.company.status == CompanyStatus.suspended) const PopupMenuItem(value: 'reinstate', child: Text('Reinstate')),
                          PopupMenuItem(value: 'verify', child: Text(c.company.verified ? 'Remove verified badge' : 'Add verified badge')),
                        ],
                      )),
                    ]),
                ],
              ),
            ]);
          },
        ),
      ],
    );
  }
}

class _CompanyStatusPill extends StatelessWidget {
  const _CompanyStatusPill(this.status);
  final CompanyStatus status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      CompanyStatus.approved => AppColors.success,
      CompanyStatus.pending => AppColors.warning,
      _ => AppColors.danger,
    };
    return TagChip(status.label, dense: true, color: color, background: color.withValues(alpha: 0.12));
  }
}

class _CompanyDialog extends StatelessWidget {
  const _CompanyDialog({required this.c});
  final AdminCompany c;

  @override
  Widget build(BuildContext context) {
    final co = c.company;
    return AlertDialog(
      title: Row(children: [CompanyLogo(company: co, size: 40), const SizedBox(width: 12), Expanded(child: Text(co.name))]),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            _CompanyStatusPill(co.status),
            const SizedBox(height: 12),
            Text(co.about.isEmpty ? 'No description.' : co.about, style: context.text.bodyMedium),
            const SizedBox(height: 12),
            InfoRow(icon: Icons.category_outlined, label: 'Industry', value: co.industry.label),
            InfoRow(icon: Icons.place_outlined, label: 'Head office', value: '${co.location}${co.address.isEmpty ? '' : ' · ${co.address}'}'),
            InfoRow(icon: Icons.mail_outline_rounded, label: 'Email', value: co.email.isEmpty ? '—' : co.email),
            InfoRow(icon: Icons.phone_outlined, label: 'Phone', value: co.phone.isEmpty ? '—' : co.phone),
            InfoRow(icon: Icons.language_rounded, label: 'Website', value: co.website.isEmpty ? '—' : co.website),
            InfoRow(icon: Icons.groups_outlined, label: 'Size · team on Vocation SL', value: '${co.size.isEmpty ? '—' : co.size} · ${c.members}'),
          ]),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
    );
  }
}

// ---- Reports ---------------------------------------------------------------------------

class AdminReportsScreen extends ConsumerStatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  ConsumerState<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends ConsumerState<AdminReportsScreen> {
  bool _openOnly = true;

  Future<void> _resolve(Report r, ReportStatus status) async {
    final note = await showDialog<String>(context: context, builder: (_) => _NoteDialog(status: status));
    if (note == null || !mounted) return;
    await _act(context, ref, 'Report marked ${status.label.toLowerCase()}',
        () => ref.read(adminActionsProvider).run((b) => b.updateReport(r.id, status, note: note), refresh: [adminReportsProvider]));
  }

  Future<void> _takeDown(Report r) async {
    final a = ref.read(adminActionsProvider);
    switch (r.targetType) {
      case ReportTarget.job:
        if (await confirmDialog(context, title: 'Take down this job?', message: '"${r.targetLabel}" will be closed.', confirmLabel: 'Close job')) {
          if (!mounted) return;
          await _act(context, ref, 'Job closed', () => a.run((b) => b.setJobStatus(r.targetId, JobStatus.closed), refresh: [adminJobsProvider]));
        }
      case ReportTarget.company:
        if (await confirmDialog(context, title: 'Suspend this company?', message: '"${r.targetLabel}" and its jobs will be hidden.', confirmLabel: 'Suspend', destructive: true)) {
          if (!mounted) return;
          await _act(context, ref, 'Company suspended',
              () => a.run((b) => b.setCompanyStatus(r.targetId, CompanyStatus.suspended), refresh: [adminCompaniesProvider]));
        }
      case ReportTarget.user:
        if (await confirmDialog(context, title: 'Suspend this user?', message: '"${r.targetLabel}" won\'t be able to apply or post jobs.', confirmLabel: 'Suspend', destructive: true)) {
          if (!mounted) return;
          await _act(context, ref, 'User suspended',
              () => a.run((b) => b.setUserSuspended(r.targetId, true, reason: r.reason), refresh: [adminUsersProvider]));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(adminReportsProvider);
    final canModerate = adminCan(ref, AdminRole.moderator);
    return EmployerPage(
      title: 'Reports',
      subtitle: 'Content flagged by job seekers and employers.',
      onRefresh: () async => ref.invalidate(adminReportsProvider),
      children: [
        AdminAsync<List<Report>>(
          value: async,
          onRetry: () => ref.invalidate(adminReportsProvider),
          builder: (all) {
            final list = all.where((r) => !_openOnly || r.status.isOpen).toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, children: [
                ChoiceChip(label: Text('Open (${all.where((r) => r.status.isOpen).length})'), selected: _openOnly, onSelected: (_) => setState(() => _openOnly = true)),
                ChoiceChip(label: Text('All (${all.length})'), selected: !_openOnly, onSelected: (_) => setState(() => _openOnly = false)),
              ]),
              const SizedBox(height: 16),
              if (list.isEmpty)
                const Card(child: EmptyState(icon: Icons.flag_outlined, title: 'No open reports', message: 'Reports from users appear here.'))
              else
                for (final r in list)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            TagChip(r.targetType.label, dense: true),
                            const SizedBox(width: 8),
                            Expanded(child: Text(r.targetLabel.isEmpty ? r.targetId : r.targetLabel, style: context.text.titleMedium)),
                            TagChip(
                              r.status.label,
                              dense: true,
                              color: r.status.isOpen ? AppColors.warning : AppColors.success,
                              background: (r.status.isOpen ? AppColors.warning : AppColors.success).withValues(alpha: 0.12),
                            ),
                          ]),
                          const SizedBox(height: 8),
                          Text(r.reason, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          if (r.details.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(r.details, style: context.text.bodyMedium)),
                          const SizedBox(height: 6),
                          Text('Reported ${Fmt.ago(r.createdAt)}', style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
                          if (r.adminNote.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text('Note: ${r.adminNote}', style: context.text.bodySmall)),
                          if (r.status.isOpen && canModerate) ...[
                            const SizedBox(height: 12),
                            Wrap(spacing: 8, runSpacing: 8, children: [
                              OutlinedButton(
                                onPressed: () => _takeDown(r),
                                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, minimumSize: const Size(0, 40)),
                                child: Text(switch (r.targetType) { ReportTarget.job => 'Take down job', ReportTarget.company => 'Suspend company', ReportTarget.user => 'Suspend user' }),
                              ),
                              if (r.status == ReportStatus.open)
                                OutlinedButton(
                                  onPressed: () => _act(context, ref, 'Marked as reviewing',
                                      () => ref.read(adminActionsProvider).run((b) => b.updateReport(r.id, ReportStatus.reviewing), refresh: [adminReportsProvider])),
                                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                                  child: const Text('Mark reviewing'),
                                ),
                              FilledButton(onPressed: () => _resolve(r, ReportStatus.resolved), style: FilledButton.styleFrom(minimumSize: const Size(0, 40)), child: const Text('Resolve')),
                              TextButton(onPressed: () => _resolve(r, ReportStatus.dismissed), child: const Text('Dismiss')),
                            ]),
                          ],
                        ]),
                      ),
                    ),
                  ),
            ]);
          },
        ),
      ],
    );
  }
}

class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.status});
  final ReportStatus status;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('${widget.status.label} report'),
        content: TextField(
          controller: _c,
          minLines: 2,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Note for the team (optional)', hintText: 'What did you do and why?'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, _c.text.trim()), style: FilledButton.styleFrom(minimumSize: const Size(64, 44)), child: Text(widget.status.label)),
        ],
      );
}
