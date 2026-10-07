import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../features/applications/application_detail_screen.dart' show ApplicationTimeline;
import '../../../models/models.dart';
import '../../../widgets/common.dart';
import '../../../widgets/skeletons.dart';
import '../../../widgets/states.dart';
import '../../providers.dart';
import '../../widgets.dart';
import 'candidates_screen.dart';

class CandidateDetailScreen extends ConsumerStatefulWidget {
  const CandidateDetailScreen({super.key, required this.applicationId});
  final String applicationId;

  @override
  ConsumerState<CandidateDetailScreen> createState() => _CandidateDetailScreenState();
}

class _CandidateDetailScreenState extends ConsumerState<CandidateDetailScreen> {
  final _message = TextEditingController();
  bool _busy = false;
  bool _markedViewed = false;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  JobApplication? get _app =>
      ref.read(candidatesProvider).value?.data.where((a) => a.id == widget.applicationId).firstOrNull;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showSnack(context, done);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _move(JobApplication a, ApplicationStatus s) async {
    if (s == ApplicationStatus.rejected &&
        !await confirmDialog(context,
            title: 'Reject ${a.applicant.fullName}?',
            message: 'They will be notified that they were not selected.',
            confirmLabel: 'Reject',
            destructive: true)) {
      return;
    }
    await _run(() => ref.read(candidatesProvider.notifier).updateCandidate(a, status: s), 'Moved to ${s.label}');
  }

  Future<void> _schedule(JobApplication a) async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: a.interviewAt ?? now.add(const Duration(days: 2)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 120)),
      helpText: 'Interview date',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 10, minute: 0), helpText: 'Interview time');
    if (time == null) return;
    final at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    final note = _message.text.trim().isEmpty
        ? 'We would like to invite you to an interview on ${Fmt.dateTime(at)}. Please reply to confirm.'
        : _message.text.trim();
    await _run(
      () => ref.read(candidatesProvider.notifier).updateCandidate(a, status: ApplicationStatus.interview, interviewAt: at, message: note),
      'Interview scheduled. ${a.applicant.fullName} has been notified.',
    );
    _message.clear();
  }

  Future<void> _send(JobApplication a) async {
    final text = _message.text.trim();
    if (text.isEmpty) return;
    await _run(() => ref.read(candidatesProvider.notifier).updateCandidate(a, message: text), 'Message sent');
    _message.clear();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(candidatesProvider);
    final a = async.value?.data.where((x) => x.id == widget.applicationId).firstOrNull;
    if (a == null) {
      return Scaffold(
        appBar: AppBar(),
        body: async.isLoading
            ? const SingleChildScrollView(child: ProfileSkeleton())
            : const EmptyState(icon: Icons.search_off_rounded, title: 'Application not found', message: 'It may have been removed.'),
      );
    }
    if (!_markedViewed) {
      _markedViewed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final current = _app;
        if (current != null) ref.read(candidatesProvider.notifier).markViewed(current);
      });
    }
    final profile = ref.watch(applicantProfileProvider(a.userId));
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final canAct = a.status != ApplicationStatus.withdrawn;

    final header = Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            UserAvatar(initials: _initials(a.applicant.fullName), photoBase64: profile.value?.photoBase64, size: 64),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(a.applicant.fullName, style: context.text.headlineSmall),
                if ((profile.value?.headline ?? '').isNotEmpty) Text(profile.value!.headline, style: context.text.bodyLarge),
                const SizedBox(height: 4),
                Text('Applied for ${a.job?.title ?? 'a job'} · ${Fmt.ago(a.submittedAt)}',
                    style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            TagChip(a.applicant.email, icon: Icons.mail_outline_rounded),
            TagChip(a.applicant.phone, icon: Icons.phone_outlined),
            TagChip(a.applicant.location, icon: Icons.place_outlined),
          ]),
        ]),
      ),
    );

    final actions = SectionCard(
      title: 'Stage',
      trailing: StatusChip(a.status),
      child: !canAct
          ? Text('The candidate withdrew this application.', style: context.text.bodyMedium)
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in [ApplicationStatus.shortlisted, ApplicationStatus.assessment, ApplicationStatus.offer, ApplicationStatus.hired])
                  OutlinedButton(
                    onPressed: _busy || a.status == s ? null : () => _move(a, s),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
                    child: Text(s.label),
                  ),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _schedule(a),
                  icon: const Icon(Icons.event_rounded, size: 18),
                  label: Text(a.interviewAt == null ? 'Schedule interview' : 'Reschedule interview'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                ),
                TextButton(
                  onPressed: _busy || a.status == ApplicationStatus.rejected ? null : () => _move(a, ApplicationStatus.rejected),
                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                  child: const Text('Reject'),
                ),
              ]),
              if (a.interviewAt != null) ...[
                const SizedBox(height: 12),
                InfoRow(icon: Icons.event_available_rounded, label: 'Interview', value: '${Fmt.dateTime(a.interviewAt!)} (${Fmt.countdown(a.interviewAt!)})'),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _message,
                minLines: 2,
                maxLines: 6,
                maxLength: 1000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Message to candidate', hintText: 'They\'ll get a notification in the app.', alignLabelWithHint: true),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.tonalIcon(
                  onPressed: _busy ? null : () => _send(a),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Send message'),
                ),
              ),
              if (a.employerMessage != null) ...[
                const SizedBox(height: 8),
                Text('Last message sent', style: context.text.labelMedium?.copyWith(color: context.palette.muted)),
                const SizedBox(height: 4),
                Text(a.employerMessage!, style: context.text.bodyMedium),
              ],
            ]),
    );

    final documents = SectionCard(
      title: 'Documents',
      child: Column(children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.danger),
          title: Text(a.resume.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('CV · ${a.resume.format.label} · ${Fmt.fileSize(a.resume.sizeBytes)}'),
          trailing: const Icon(Icons.open_in_new_rounded),
          onTap: () => openDocument(context, ref, a.resume.storagePath),
        ),
        if (a.coverLetter?.kind == CoverLetterKind.uploaded)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: Text(a.coverLetter!.fileName ?? 'Cover letter'),
            subtitle: const Text('Cover letter'),
            trailing: const Icon(Icons.open_in_new_rounded),
            onTap: () => openDocument(context, ref, a.coverLetter!.storagePath),
          ),
        if (a.coverLetter?.kind == CoverLetterKind.written) ...[
          const Divider(),
          Align(alignment: Alignment.centerLeft, child: Text('Cover letter', style: context.text.labelLarge)),
          const SizedBox(height: 6),
          SelectableText(a.coverLetter!.text ?? '', style: context.text.bodyMedium),
        ],
        if (a.coverLetter == null)
          Align(alignment: Alignment.centerLeft, child: Text('No cover letter', style: context.text.bodySmall?.copyWith(color: context.palette.muted))),
        if (a.note != null) ...[
          const Divider(),
          Align(alignment: Alignment.centerLeft, child: Text('Note from candidate', style: context.text.labelLarge)),
          const SizedBox(height: 6),
          Align(alignment: Alignment.centerLeft, child: Text(a.note!, style: context.text.bodyMedium)),
        ],
      ]),
    );

    final profileCard = SectionCard(
      title: 'Profile',
      child: profile.when(
        loading: () => const Skeleton(child: Column(children: [ListTileSkeleton(), ListTileSkeleton()])),
        error: (e, _) => Text('Couldn\'t load the full profile.', style: context.text.bodyMedium),
        data: (u) => u == null
            ? Text('Profile not available.', style: context.text.bodyMedium)
            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (u.about.isNotEmpty) Text(u.about, style: context.text.bodyMedium),
                if (u.skills.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Skills', style: context.text.labelLarge),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final s in u.skills)
                      (a.job?.skills.any((k) => k.toLowerCase() == s.toLowerCase()) ?? false)
                          ? TagChip(s, dense: true, icon: Icons.check_rounded, color: context.colors.onPrimaryContainer, background: context.colors.primaryContainer)
                          : TagChip(s, dense: true),
                  ]),
                ],
                if (u.experience.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Experience', style: context.text.labelLarge),
                  for (final e in u.experience)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('${e.title} · ${e.company} (${Fmt.monthYear(e.start)} – ${e.end == null ? 'Present' : Fmt.monthYear(e.end!)})',
                          style: context.text.bodyMedium),
                    ),
                ],
                if (u.education.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Education', style: context.text.labelLarge),
                  for (final e in u.education)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('${e.degree} ${e.field}, ${e.school} (${e.endYear ?? 'ongoing'})', style: context.text.bodyMedium),
                    ),
                ],
                if (u.languages.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Languages', style: context.text.labelLarge),
                  const SizedBox(height: 6),
                  Text(u.languages.map((l) => '${l.name} (${l.level})').join(', '), style: context.text.bodyMedium),
                ],
                if (u.linkedinUrl.isNotEmpty || u.portfolioUrl.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  if (u.linkedinUrl.isNotEmpty) SelectableText('LinkedIn: ${u.linkedinUrl}', style: context.text.bodySmall),
                  if (u.portfolioUrl.isNotEmpty) SelectableText('Portfolio: ${u.portfolioUrl}', style: context.text.bodySmall),
                ],
              ]),
      ),
    );

    final history = SectionCard(title: 'History', child: ApplicationTimeline(application: a));

    return Scaffold(
      appBar: AppBar(title: const Text('Candidate')),
      body: ResponsiveCenter(
        maxWidth: 1200,
        child: ListView(padding: const EdgeInsets.all(AppSpacing.gutter), children: [
          header,
          const SizedBox(height: 16),
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 3, child: Column(children: [actions, const SizedBox(height: 16), profileCard])),
              const SizedBox(width: 16),
              Expanded(flex: 2, child: Column(children: [documents, const SizedBox(height: 16), history])),
            ])
          else ...[
            actions,
            const SizedBox(height: 16),
            documents,
            const SizedBox(height: 16),
            profileCard,
            const SizedBox(height: 16),
            history,
          ],
        ]),
      ),
    );
  }
}

String _initials(String name) {
  final p = name.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
  if (p.isEmpty) return '?';
  return p.length > 1 ? '${p.first[0]}${p.last[0]}'.toUpperCase() : p.first[0].toUpperCase();
}
