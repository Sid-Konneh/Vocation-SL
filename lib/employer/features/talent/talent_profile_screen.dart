import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/models.dart';
import '../../../providers/hiring_providers.dart';
import '../../../widgets/common.dart';
import '../../../widgets/skeletons.dart';
import '../../../widgets/states.dart';
import '../../providers.dart';
import '../../widgets.dart';

/// Picks one of the company's live jobs and invites [person] to apply.
/// Returns the job they were invited to, or null.
Future<Job?> inviteTalent(BuildContext context, WidgetRef ref, {required String userId, required String name, required List<String> alreadyInvited}) async {
  final jobs = (ref.read(employerJobsProvider).value?.data ?? const <Job>[])
      .where((j) => j.status == JobStatus.published && !j.isClosed && !alreadyInvited.contains(j.id))
      .toList();
  if (jobs.isEmpty) {
    showSnack(context, alreadyInvited.isEmpty ? 'Post a job first; you can invite people to live jobs.' : 'You\'ve invited them to all your live jobs.',
        error: true);
    return null;
  }
  final r = await showDialog<(Job, String)>(context: context, builder: (_) => InviteToApplyDialog(name: name, jobs: jobs));
  if (r == null || !context.mounted) return null;
  try {
    await ref.read(hiringBackendProvider).inviteToApply(userId, r.$1.id, note: r.$2);
    if (context.mounted) showSnack(context, '${name.split(' ').first} has been invited to apply for ${r.$1.title}');
    return r.$1;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return null;
  }
}

class InviteToApplyDialog extends StatefulWidget {
  const InviteToApplyDialog({super.key, required this.name, required this.jobs});
  final String name;
  final List<Job> jobs;

  @override
  State<InviteToApplyDialog> createState() => _InviteToApplyDialogState();
}

class _InviteToApplyDialogState extends State<InviteToApplyDialog> {
  late Job _job = widget.jobs.first;
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Invite ${widget.name.split(' ').first} to apply'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              DropdownButtonFormField<Job>(
                initialValue: _job,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Job'),
                items: [for (final j in widget.jobs) DropdownMenuItem(value: j, child: Text(j.title, overflow: TextOverflow.ellipsis))],
                onChanged: (v) => setState(() => _job = v ?? _job),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                maxLength: 500,
                minLines: 2,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Short note (optional)',
                  hintText: 'Why you think they\'d be a good fit',
                  alignLabelWithHint: true,
                ),
              ),
              Text('They get a notification and can open the job. You see their contact details and CV if they apply.',
                  style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, (_job, _note.text)), child: const Text('Send invitation')),
        ],
      );
}

final _talentProfileProvider = FutureProvider.autoDispose.family<AppUser, String>(
  (ref, userId) => ref.watch(hiringBackendProvider).talentProfile(userId),
);

/// Everything a job seeker who chose to be found shares with employers.
class TalentProfileScreen extends ConsumerStatefulWidget {
  const TalentProfileScreen({super.key, required this.userId, this.invitedJobIds = const []});
  final String userId;
  final List<String> invitedJobIds;

  @override
  ConsumerState<TalentProfileScreen> createState() => _TalentProfileScreenState();
}

class _TalentProfileScreenState extends ConsumerState<TalentProfileScreen> {
  late final _invited = List.of(widget.invitedJobIds);

  Future<void> _invite(AppUser u) async {
    final job = await inviteTalent(context, ref, userId: u.id, name: u.fullName, alreadyInvited: _invited);
    if (job != null) setState(() => _invited.add(job.id));
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_talentProfileProvider(widget.userId));
    final jobs = ref.watch(employerJobsProvider).value?.data ?? const <Job>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Talent profile')),
      bottomNavigationBar: async.value == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: () => _invite(async.value!),
                  icon: const Icon(Icons.mark_email_unread_outlined),
                  label: const Text('Invite to apply'),
                ),
              ),
            ),
      body: async.when(
        loading: () => const SingleChildScrollView(child: ProfileSkeleton()),
        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(_talentProfileProvider(widget.userId))),
        data: (u) {
          final muted = context.palette.muted;
          final invitedTo = [for (final j in jobs) if (_invited.contains(j.id)) j.title];
          final prefs = u.preferences;
          return ResponsiveCenter(
            maxWidth: 900,
            child: ListView(padding: const EdgeInsets.all(AppSpacing.gutter), children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(children: [
                    UserAvatar(initials: u.fullName.trim().isEmpty ? '?' : u.initials, photoBase64: u.photoBase64, size: 72),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(u.fullName, style: context.text.headlineSmall),
                        if (u.headline.isNotEmpty) Text(u.headline, style: context.text.bodyLarge),
                        if (u.location.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(children: [
                              Icon(Icons.place_outlined, size: 16, color: muted),
                              const SizedBox(width: 4),
                              Flexible(child: Text(u.location, style: context.text.bodyMedium?.copyWith(color: muted))),
                            ]),
                          ),
                      ]),
                    ),
                  ]),
                ),
              ),
              if (invitedTo.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Invited to: ${invitedTo.join(', ')}', style: context.text.bodyMedium?.copyWith(color: AppColors.green, fontWeight: FontWeight.w600)),
              ],
              if (u.about.isNotEmpty) ...[
                const SizedBox(height: 16),
                SectionCard(title: 'About', child: SelectableText(u.about, style: context.text.bodyLarge)),
              ],
              if (u.skills.isNotEmpty) ...[
                const SizedBox(height: 16),
                SectionCard(title: 'Skills', child: Wrap(spacing: 6, runSpacing: 6, children: [for (final s in u.skills) TagChip(s, dense: true)])),
              ],
              if (u.experience.isNotEmpty) ...[
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Experience',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final e in u.experience)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(e.title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          Text([e.company, e.location].where((s) => s.trim().isNotEmpty).join(' · '), style: context.text.bodyMedium),
                          Text('${Fmt.monthYear(e.start)} – ${e.end == null ? 'Present' : Fmt.monthYear(e.end!)}',
                              style: context.text.bodySmall?.copyWith(color: muted)),
                          if (e.description.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(e.description.trim(), style: context.text.bodyMedium),
                          ],
                        ]),
                      ),
                  ]),
                ),
              ],
              if (u.education.isNotEmpty) ...[
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Education',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final e in u.education)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(e.school, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                          Text([e.degree, e.field].where((s) => s.trim().isNotEmpty).join(', '), style: context.text.bodyMedium),
                          Text('${e.startYear == 0 ? '' : '${e.startYear} – '}${e.endYear ?? 'ongoing'}', style: context.text.bodySmall?.copyWith(color: muted)),
                        ]),
                      ),
                  ]),
                ),
              ],
              if (u.certifications.isNotEmpty) ...[
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Certifications',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final c in u.certifications)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text([c.name, c.issuer, if (c.year > 0) '${c.year}'].where((s) => s.trim().isNotEmpty).join(' · '),
                            style: context.text.bodyMedium),
                      ),
                  ]),
                ),
              ],
              if (u.languages.isNotEmpty) ...[
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Languages',
                  child: Text(u.languages.map((l) => l.level.isEmpty ? l.name : '${l.name} (${l.level})').join(', '), style: context.text.bodyMedium),
                ),
              ],
              if (!prefs.isEmpty || prefs.workModes.isNotEmpty || prefs.employmentTypes.isNotEmpty) ...[
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Looking for',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (prefs.titles.isNotEmpty) InfoRow(icon: Icons.work_outline_rounded, label: 'Roles', value: prefs.titles.join(', ')),
                    if (prefs.industries.isNotEmpty)
                      InfoRow(icon: Icons.category_outlined, label: 'Fields', value: prefs.industries.map((i) => i.label).join(', ')),
                    if (prefs.locations.isNotEmpty) InfoRow(icon: Icons.place_outlined, label: 'Places', value: prefs.locations.join(', ')),
                    if (prefs.employmentTypes.isNotEmpty)
                      InfoRow(icon: Icons.schedule_rounded, label: 'Contract', value: prefs.employmentTypes.map((t) => t.label).join(', ')),
                    if (prefs.workModes.isNotEmpty)
                      InfoRow(icon: Icons.wifi_rounded, label: 'Work mode', value: prefs.workModes.map((m) => m.label).join(', ')),
                  ]),
                ),
              ],
              if (u.linkedinUrl.isNotEmpty || u.portfolioUrl.isNotEmpty) ...[
                const SizedBox(height: 16),
                SectionCard(
                  title: 'Links',
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    for (final (label, url) in [('LinkedIn', u.linkedinUrl), ('Portfolio', u.portfolioUrl)])
                      if (url.isNotEmpty)
                        TextButton.icon(
                          onPressed: () => launchUrl(Uri.parse(url.startsWith('http') ? url : 'https://$url'), mode: LaunchMode.externalApplication),
                          icon: const Icon(Icons.open_in_new_rounded, size: 18),
                          label: Text('$label: $url', overflow: TextOverflow.ellipsis),
                        ),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(AppSpacing.radius)),
                child: Row(children: [
                  Icon(Icons.lock_outline_rounded, size: 18, color: muted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Phone, email and CV are shared when ${u.fullName.split(' ').first} applies. Invite them to apply to one of your jobs.',
                        style: context.text.bodySmall?.copyWith(color: muted)),
                  ),
                ]),
              ),
              const SizedBox(height: 24),
            ]),
          );
        },
      ),
    );
  }
}
