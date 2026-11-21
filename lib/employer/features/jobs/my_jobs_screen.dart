import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/models.dart';
import '../../../admin/admin_providers.dart';
import '../../../providers/core_providers.dart';
import '../../../services/share_service.dart';
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
        case 'share':
          final copied = await ref.read(shareServiceProvider).shareText(
            '${job.title} at ${job.companyName}\nApply on Vocation SL: ${ShareService.jobLink(job.id)}',
            subject: '${job.title} – ${job.companyName}',
          );
          if (copied && mounted) showSnack(context, 'Job link copied. Paste it into WhatsApp, Facebook or email.');
        case 'copy':
          await Clipboard.setData(ClipboardData(text: ShareService.jobLink(job.id)));
          if (mounted) showSnack(context, 'Job link copied');
        case 'feature':
          final price = (await ref.read(platformSettingsProvider.future)).featuredPrice;
          if (!mounted) return;
          final ok = await confirmDialog(
            context,
            title: 'Feature this job?',
            message: 'Featured jobs appear at the top of the job seekers\' home screen until they close. '
                'Price: SLE ${Fmt.money(price)} + 15% GST. We\'ll send you an invoice; the job is featured once it\'s paid.',
            confirmLabel: 'Request featuring',
          );
          if (!ok) return;
          final number = await ref.read(employerBackendProvider).requestFeatured(job.id);
          await ctrl.refresh();
          if (mounted) showSnack(context, 'Request sent. Invoice $number is in Invoices.');
        case 'applicants':
          context.go('/employer/candidates?job=${job.id}');
        case 'report':
          context.push('/employer/jobs/${job.id}/report');
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
        case 'extend' || 'repost':
          await _extend(job);
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

  /// Extend a live job, or repost a closed one, by 1 to 4 weeks.
  Future<void> _extend(Job job) async {
    final s = await ref.read(platformSettingsProvider.future);
    final company = ref.read(companyProvider).value?.data;
    if (!mounted) return;
    final free = company != null && s.freePostingCompanies.contains(company.id);
    final weeks = await showDialog<int>(context: context, builder: (_) => _ExtendDialog(job: job, pricePerWeek: s.extensionPrice, free: free));
    if (weeks == null || !mounted) return;
    final r = await ref.read(employerJobsProvider.notifier).extend(job, weeks);
    if (!mounted) return;
    final what = job.status == JobStatus.closed ? 'Job reposted' : 'Job extended';
    final live = r.status == JobStatus.pending ? ' It goes live once your company is approved.' : '';
    final bill = r.free ? '' : " We'll send you invoice ${r.invoice} for the extra ${weeks == 1 ? 'week' : 'weeks'}.";
    showSnack(context, '$what until ${Fmt.date(r.deadline)}.$live$bill');
  }

  /// Busy employers send us their advert and we post it for them.
  Future<void> _postForMe() => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("We'll post it for you"),
          content: const Text(
            'Busy? Send us your job advert (a photo, PDF or Word file) on WhatsApp or by email. '
            "We'll post it for your company, usually the same day, and you manage applicants here as usual.",
          ),
          actions: [
            TextButton.icon(
              onPressed: () => launchUrl(Uri.parse('mailto:info@vocationsl.com?subject=Please%20post%20our%20job'), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.email_outlined),
              label: const Text('Email'),
            ),
            FilledButton.icon(
              onPressed: () => launchUrl(
                Uri.parse('https://wa.me/23273512413?text=${Uri.encodeComponent('Hello Vocation SL, please post our job. Our advert is attached.')}'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(Icons.chat_outlined),
              label: const Text('WhatsApp'),
            ),
          ],
        ),
      );

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
        OutlinedButton.icon(
          onPressed: _postForMe,
          icon: const Icon(Icons.support_agent_rounded),
          label: const Text('Post it for me'),
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
        ),
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
                            if (j.featured || j.featureRequested)
                              Text(
                                j.featured ? '★ Featured on the home screen' : 'Featuring requested, pending payment',
                                style: context.text.bodySmall?.copyWith(color: j.featured ? AppColors.green : AppColors.warning, fontWeight: FontWeight.w600),
                              )
                            else if (j.reviewNote.isNotEmpty && (j.status == JobStatus.declined || j.status == JobStatus.rejected))
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
                    DataCell(j.appliesExternally
                        ? Tooltip(
                            message: '${j.applyClicks} taps on apply. ${j.externalApplied} told us they applied. Applications go to your own link.',
                            child: Text('${j.externalApplied} applied · ${j.applyClicks} taps'),
                          )
                        : Text('${j.applicants}')),
                    DataCell(Text('${j.views}')),
                    DataCell(Text(j.status == JobStatus.draft ? '—' : Fmt.dateShort(j.postedAt))),
                    DataCell(
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          Fmt.deadline(j.deadline),
                          style: TextStyle(color: j.isClosed ? AppColors.danger : (Fmt.deadlineSoon(j.deadline) ? AppColors.warning : null)),
                        ),
                        if (j.status == JobStatus.closed || (j.status == JobStatus.published && (j.isClosed || Fmt.deadlineSoon(j.deadline))))
                          TextButton(
                            onPressed: () => _act(j, j.status == JobStatus.closed ? 'repost' : 'extend'),
                            child: Text(j.status == JobStatus.closed ? 'Repost' : 'Extend'),
                          ),
                      ]),
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
                          if (j.status == JobStatus.published) ...[
                            const PopupMenuItem(value: 'share', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.share_rounded), title: Text('Share job link'))),
                            const PopupMenuItem(value: 'copy', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.link_rounded), title: Text('Copy job link'))),
                          ],
                          if (j.status == JobStatus.published && !j.featured && !j.featureRequested)
                            const PopupMenuItem(value: 'feature', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.star_outline_rounded), title: Text('Feature this job'))),
                          if (j.status != JobStatus.draft && !j.appliesExternally) const PopupMenuItem(value: 'applicants', child: Text('View applicants')),
                          if (j.status == JobStatus.published || j.status == JobStatus.closed)
                            const PopupMenuItem(value: 'report', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.bar_chart_rounded), title: Text('Hiring report'))),
                          if (j.status == JobStatus.published)
                            const PopupMenuItem(value: 'extend', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.update_rounded), title: Text('Extend (add weeks)'))),
                          if (j.status == JobStatus.closed)
                            const PopupMenuItem(value: 'repost', child: ListTile(dense: true, contentPadding: EdgeInsets.zero, leading: Icon(Icons.replay_rounded), title: Text('Repost for more weeks'))),
                          if (j.status == JobStatus.published) const PopupMenuItem(value: 'close', child: Text('Close job')),
                          if (j.status == JobStatus.closed && j.deadline.isAfter(DateTime.now())) const PopupMenuItem(value: 'reopen', child: Text('Reopen until the deadline')),
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

/// Choose how many weeks to add (1 to 4), with the price and the new deadline.
class _ExtendDialog extends StatefulWidget {
  const _ExtendDialog({required this.job, required this.pricePerWeek, required this.free});
  final Job job;
  final int pricePerWeek;
  final bool free;

  @override
  State<_ExtendDialog> createState() => _ExtendDialogState();
}

class _ExtendDialogState extends State<_ExtendDialog> {
  int _weeks = 1;

  DateTime get _newDeadline {
    final now = DateTime.now();
    final from = widget.job.deadline.isAfter(now) ? widget.job.deadline : now;
    return DateTime(from.year, from.month, from.day + 7 * _weeks);
  }

  @override
  Widget build(BuildContext context) {
    final repost = widget.job.status == JobStatus.closed;
    final price = widget.pricePerWeek * _weeks;
    final gst = (price * 0.15).round();
    return AlertDialog(
      title: Text(repost ? 'Repost this job' : 'Extend this job'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.job.title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text('How many more weeks?', style: context.text.bodyMedium),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: [for (final w in [1, 2, 3, 4]) ButtonSegment(value: w, label: Text(w == 1 ? '1 week' : '$w weeks'))],
            selected: {_weeks},
            showSelectedIcon: false,
            onSelectionChanged: (v) => setState(() => _weeks = v.first),
          ),
          const SizedBox(height: 14),
          Text('New deadline: ${Fmt.date(_newDeadline)}', style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            widget.free
                ? 'Free for your company.'
                : 'SLE ${Fmt.money(widget.pricePerWeek)} a week: SLE ${Fmt.money(price)} + 15% GST (SLE ${Fmt.money(gst)}) = SLE ${Fmt.money(price + gst)}. '
                    "We'll send you an invoice; pay within 14 days by Mobile Money or bank transfer.",
            style: context.text.bodySmall?.copyWith(color: context.palette.muted),
          ),
          if (repost) ...[
            const SizedBox(height: 6),
            Text('The job opens again for applications. Applicants you already have stay in your pipeline.',
                style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, _weeks), child: Text(repost ? 'Repost job' : 'Extend job')),
      ],
    );
  }
}
