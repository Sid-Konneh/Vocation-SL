import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/user_data_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/company_logo.dart';
import '../../widgets/document_viewer.dart';
import '../../widgets/message_thread.dart';
import '../../providers/core_providers.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';

class ApplicationDetailScreen extends ConsumerWidget {
  const ApplicationDetailScreen({super.key, required this.applicationId});
  final String applicationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(applicationsProvider);
    final app = ref.watch(applicationByIdProvider(applicationId));

    if (async.isLoading && app == null) {
      return Scaffold(appBar: AppBar(), body: const SingleChildScrollView(child: JobDetailSkeleton()));
    }
    if (app == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.hasError
            ? ErrorState(error: async.error!, onRetry: () => ref.invalidate(applicationsProvider))
            : const EmptyState(icon: Icons.search_off_rounded, title: 'Application not found', message: 'It may have been removed.'),
      );
    }
    return _Detail(app: app);
  }
}

class _Detail extends ConsumerStatefulWidget {
  const _Detail({required this.app});
  final JobApplication app;

  @override
  ConsumerState<_Detail> createState() => _DetailState();
}

class _DetailState extends ConsumerState<_Detail> {
  bool _withdrawing = false;

  Future<void> _withdraw() async {
    final reason = await showDialog<String>(context: context, builder: (_) => const _WithdrawDialog());
    if (reason == null || !mounted) return;
    setState(() => _withdrawing = true);
    try {
      await ref.read(applicationsProvider.notifier).withdraw(widget.app, reason: reason.isEmpty ? null : reason);
      if (mounted) showSnack(context, 'Application withdrawn');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _withdrawing = false);
    }
  }

  void _showCoverLetter(String text) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (context, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(24, 0, 24, 32), children: [
            Text('Cover letter', style: context.text.titleLarge),
            const SizedBox(height: 16),
            SelectableText(text, style: context.text.bodyLarge),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final a = widget.app;
    final job = a.job;
    final muted = context.palette.muted;

    return Scaffold(
      appBar: AppBar(title: const Text('Application')),
      body: RefreshIndicator(
        onRefresh: () => ref.read(applicationsProvider.notifier).refresh(),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSpacing.maxReadingWidth),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, AppSpacing.gutter, 40),
              children: [
                InkWell(
                  onTap: job == null ? null : () => context.push('/job/${job.id}'),
                  borderRadius: BorderRadius.circular(12),
                  child: Row(children: [
                    CompanyLogo(company: job?.company, size: 56, name: job?.companyName),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(job?.title ?? 'Job no longer listed', style: context.text.titleLarge),
                        Text('${job?.companyName ?? ''} · ${job?.location ?? ''}', style: context.text.bodyMedium?.copyWith(color: muted)),
                      ]),
                    ),
                    if (job != null) const Icon(Icons.chevron_right_rounded),
                  ]),
                ),
                const SizedBox(height: 18),
                Row(children: [
                  StatusChip(a.status),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Updated ${Fmt.ago(a.updatedAt).toLowerCase()}', style: context.text.bodySmall?.copyWith(color: muted))),
                ]),
                const SizedBox(height: 8),
                Text(a.status.description, style: context.text.bodyLarge),
                if (a.pendingSync) ...[
                  const SizedBox(height: 16),
                  const _Callout(
                    icon: Icons.cloud_upload_outlined,
                    color: AppColors.warning,
                    title: 'Waiting to send',
                    body: 'You applied while offline. This application will be submitted automatically when you reconnect.',
                  ),
                ],
                if (a.interviewAt != null && a.status == ApplicationStatus.interview) ...[
                  const SizedBox(height: 16),
                  _Callout(
                    icon: Icons.event_available_rounded,
                    color: const Color(0xFFD9570F),
                    title: 'Interview ${Fmt.countdown(a.interviewAt!)}',
                    body: Fmt.dateTime(a.interviewAt!),
                  ),
                ],
                if (a.nextStepDeadline != null && a.status.isActive) ...[
                  const SizedBox(height: 16),
                  _Callout(
                    icon: Icons.timer_outlined,
                    color: AppColors.warning,
                    title: 'Next step due ${Fmt.countdown(a.nextStepDeadline!)}',
                    body: Fmt.dateTime(a.nextStepDeadline!),
                  ),
                ],
                if (!a.pendingSync)
                  _Section(
                    title: 'Messages',
                    child: MessageThread(
                      applicationId: a.id,
                      asEmployer: false,
                      otherName: (job?.companyName ?? '').isEmpty ? 'the employer' : job!.companyName,
                      legacyEmployerMessage: a.employerMessage,
                      enabled: a.status != ApplicationStatus.withdrawn,
                    ),
                  ),
                _Section(title: 'Progress', child: ApplicationTimeline(application: a)),
                _Section(
                  title: 'Status history',
                  child: Column(children: [
                    for (final e in a.history.reversed)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(StatusChip.iconFor(e.status), color: StatusChip.colorFor(e.status)),
                        title: Text(e.status.label, style: context.text.titleSmall),
                        subtitle: Text([Fmt.dateTime(e.at), if (e.note != null) e.note!].join('\n')),
                        isThreeLine: e.note != null,
                      ),
                  ]),
                ),
                _Section(
                  title: 'Submitted documents',
                  child: Column(children: [
                    _DocTile(
                      icon: Icons.picture_as_pdf_outlined,
                      title: a.resume.fileName,
                      subtitle: 'CV · ${a.resume.format.label} · ${Fmt.fileSize(a.resume.sizeBytes)} · tap to view',
                      onTap: () => viewDocument(context,
                          title: 'Your CV',
                          fileName: a.resume.fileName,
                          format: a.resume.format,
                          storagePath: a.resume.storagePath,
                          loadUrl: ref.read(backendProvider).documentUrl),
                    ),
                    if (a.coverLetter != null)
                      _DocTile(
                        icon: a.coverLetter!.kind == CoverLetterKind.written ? Icons.edit_note_rounded : Icons.description_outlined,
                        title: a.coverLetter!.displayName,
                        subtitle: a.coverLetter!.kind == CoverLetterKind.written
                            ? 'Cover letter · tap to read'
                            : 'Cover letter · ${a.coverLetter!.format?.label ?? ''} · ${Fmt.fileSize(a.coverLetter!.sizeBytes ?? 0)} · tap to view',
                        onTap: a.coverLetter!.kind == CoverLetterKind.written
                            ? (a.coverLetter!.text == null ? null : () => _showCoverLetter(a.coverLetter!.text!))
                            : () => viewDocument(context,
                                title: 'Your cover letter',
                                fileName: a.coverLetter!.fileName ?? 'Cover letter',
                                format: a.coverLetter!.format,
                                storagePath: a.coverLetter!.storagePath,
                                loadUrl: ref.read(backendProvider).documentUrl),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(children: [Text('No cover letter included', style: context.text.bodyMedium?.copyWith(color: muted))]),
                      ),
                  ]),
                ),
                if (a.note != null) _Section(title: 'Your note to the employer', child: Text(a.note!, style: context.text.bodyLarge)),
                _Section(
                  title: 'Details',
                  child: Column(children: [
                    InfoRow(icon: Icons.person_outline_rounded, label: 'Applicant', value: '${a.applicant.fullName}\n${a.applicant.email}\n${a.applicant.phone}'),
                    InfoRow(icon: Icons.send_outlined, label: 'Submitted', value: Fmt.dateTime(a.submittedAt)),
                    if (job != null)
                      InfoRow(icon: Icons.event_outlined, label: 'Job deadline', value: '${Fmt.date(job.deadline)} · ${Fmt.deadline(job.deadline)}'),
                    InfoRow(icon: Icons.tag_rounded, label: 'Reference', value: a.id.substring(0, a.id.length.clamp(0, 8)).toUpperCase()),
                  ]),
                ),
                if (a.status.isActive && !a.pendingSync) ...[
                  const SizedBox(height: 28),
                  OutlinedButton.icon(
                    onPressed: _withdrawing ? null : _withdraw,
                    icon: _withdrawing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.undo_rounded),
                    label: const Text('Withdraw application'),
                    style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger, side: const BorderSide(color: AppColors.danger)),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Vertical pipeline: completed steps filled, current highlighted, upcoming muted.
class ApplicationTimeline extends StatelessWidget {
  const ApplicationTimeline({super.key, required this.application});
  final JobApplication application;

  @override
  Widget build(BuildContext context) {
    final a = application;
    final reached = {for (final e in a.history) e.status: e.at};
    final terminal = a.status == ApplicationStatus.rejected || a.status == ApplicationStatus.withdrawn;

    // Steps to draw: pipeline up to the furthest reached step, then either
    // the terminal state or the remaining upcoming steps.
    final pipeline = ApplicationStatus.pipeline;
    var furthest = 0;
    for (var i = 0; i < pipeline.length; i++) {
      if (reached.containsKey(pipeline[i])) furthest = i;
    }
    final steps = <ApplicationStatus>[
      ...pipeline.take(furthest + 1).where((s) => reached.containsKey(s) || s == ApplicationStatus.applied),
      if (terminal) a.status else ...pipeline.skip(furthest + 1),
    ];

    return Column(children: [
      for (var i = 0; i < steps.length; i++)
        _TimelineRow(
          status: steps[i],
          at: reached[steps[i]],
          state: steps[i] == a.status ? _NodeState.current : (reached.containsKey(steps[i]) ? _NodeState.done : _NodeState.upcoming),
          isLast: i == steps.length - 1,
        ),
    ]);
  }
}

enum _NodeState { done, current, upcoming }

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.status, required this.at, required this.state, required this.isLast});
  final ApplicationStatus status;
  final DateTime? at;
  final _NodeState state;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final color = StatusChip.colorFor(status);
    final upcoming = state == _NodeState.upcoming;
    final nodeColor = upcoming ? context.palette.border : color;
    return Semantics(
      label: '${status.label}, ${switch (state) { _NodeState.done => 'completed', _NodeState.current => 'current step', _NodeState.upcoming => 'not reached yet' }}${at != null ? ', ${Fmt.date(at!)}' : ''}',
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 36,
            child: Column(children: [
              Container(
                width: state == _NodeState.current ? 30 : 24,
                height: state == _NodeState.current ? 30 : 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: upcoming ? context.colors.surface : nodeColor,
                  border: Border.all(color: nodeColor, width: 2),
                  boxShadow: state == _NodeState.current ? [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10)] : null,
                ),
                child: upcoming ? null : Icon(state == _NodeState.done ? Icons.check_rounded : StatusChip.iconFor(status), size: 15, color: Colors.white),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: upcoming || state == _NodeState.current ? context.palette.border : color.withValues(alpha: 0.6),
                  ),
                ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20, top: state == _NodeState.current ? 4 : 2),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(status.label,
                    style: context.text.titleSmall?.copyWith(
                      fontWeight: state == _NodeState.current ? FontWeight.w800 : FontWeight.w600,
                      color: upcoming ? context.palette.muted : null,
                    )),
                if (at != null) Text(Fmt.dateTime(at!), style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true, child: Text(title, style: context.text.titleMedium)),
          const SizedBox(height: 12),
          child,
        ]),
      );
}

class _Callout extends StatelessWidget {
  const _Callout({required this.icon, required this.color, required this.title, required this.body});
  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppSpacing.radius)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(body, style: context.text.bodyMedium),
            ]),
          ),
        ]),
      );
}

class _DocTile extends StatelessWidget {
  const _DocTile({required this.icon, required this.title, required this.subtitle, this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Card(
          child: ListTile(
            onTap: onTap,
            leading: Icon(icon, color: context.colors.primary),
            title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(subtitle),
            trailing: onTap == null ? null : const Icon(Icons.chevron_right_rounded),
          ),
        ),
      );
}

class _WithdrawDialog extends StatefulWidget {
  const _WithdrawDialog();

  @override
  State<_WithdrawDialog> createState() => _WithdrawDialogState();
}

class _WithdrawDialogState extends State<_WithdrawDialog> {
  static const _reasons = ['I accepted another offer', 'The role is no longer a good fit', 'Personal reasons', 'Other'];
  String? _reason;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Withdraw application?'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('The employer will be told you\'re no longer interested. You can\'t undo this.'),
            const SizedBox(height: 12),
            RadioGroup<String>(
              groupValue: _reason,
              onChanged: (v) => setState(() => _reason = v),
              child: Column(children: [
                for (final r in _reasons) RadioListTile<String>(contentPadding: EdgeInsets.zero, value: r, title: Text(r)),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Keep application')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger, minimumSize: const Size(64, 44)),
            onPressed: () => Navigator.pop(context, _reason ?? ''),
            child: const Text('Withdraw'),
          ),
        ],
      );
}
