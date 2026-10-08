import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/core_providers.dart';
import '../../providers/session_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/document_viewer.dart';
import 'cv_autofill.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(tooltip: 'Settings', onPressed: () => context.push('/settings'), icon: const Icon(Icons.settings_outlined)),
        ],
      ),
      body: async.when(
        loading: () => const SingleChildScrollView(child: ProfileSkeleton()),
        error: (e, _) => ErrorState(error: e, onRetry: () => ref.invalidate(profileProvider)),
        data: (loaded) => RefreshIndicator(
          onRefresh: () => ref.read(profileProvider.notifier).refresh(),
          child: _ProfileBody(user: loaded.data, offline: loaded.isOfflineCopy, syncedAt: loaded.syncedAt),
        ),
      ),
    );
  }
}

class _ProfileBody extends ConsumerStatefulWidget {
  const _ProfileBody({required this.user, required this.offline, required this.syncedAt});
  final AppUser user;
  final bool offline;
  final DateTime? syncedAt;

  @override
  ConsumerState<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends ConsumerState<_ProfileBody> {
  bool _uploadingCv = false;

  void _edit(String section) => context.push('/profile/edit?section=$section');

  Future<void> _save(AppUser u, String message) async {
    final synced = await ref.read(profileProvider.notifier).save(u);
    if (mounted) showSnack(context, synced ? message : '$message. Will sync when you\'re online.');
  }

  Future<void> _pickPhoto() async {
    try {
      final f = await ref.read(fileServiceProvider).pickPhoto();
      if (f == null) return;
      await _save(widget.user.copyWith(photoBase64: () => base64Encode(f.bytes)), 'Profile photo updated');
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _uploadCv() async {
    try {
      final f = await ref.read(fileServiceProvider).pickDocument();
      if (f == null) return;
      setState(() => _uploadingCv = true);
      final path = await ref.read(userRepositoryProvider).uploadDocument(widget.user.id, f.name, f.bytes);
      final resume = Resume(
        id: const Uuid().v4(),
        fileName: f.name,
        sizeBytes: f.size,
        uploadedAt: DateTime.now(),
        format: f.format!,
        storagePath: path,
      );
      final withCv = widget.user.copyWith(resume: () => resume);
      await _save(withCv, 'CV uploaded');
      if (!mounted) return;
      setState(() => _uploadingCv = false);
      await _offerAutofill(withCv, path);
    } on NetworkException {
      if (mounted) showSnack(context, 'You\'re offline. Connect to the internet to upload your CV.', error: true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploadingCv = false);
    }
  }

  /// Offers to fill empty profile sections from the CV just uploaded.
  Future<void> _offerAutofill(AppUser user, String? path) async {
    final ok = await confirmDialog(
      context,
      title: 'Fill your profile from this CV?',
      message: 'We can read your CV and suggest your experience, education, skills and more. You choose what to add.',
      confirmLabel: 'Fill my profile',
    );
    if (!ok || !mounted) return;
    await _fillFromCv(user, path);
  }

  Future<void> _fillFromCv(AppUser user, String? path) async {
    final updated = await fillProfileFromCv(context, ref, user, path);
    if (updated != null && mounted) await _save(updated, 'Profile updated from your CV');
  }

  @override
  Widget build(BuildContext context) {
    final u = widget.user;
    final muted = context.palette.muted;
    final prefs = u.preferences;

    return ResponsiveCenter(
      maxWidth: AppSpacing.maxReadingWidth,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, AppSpacing.gutter, 40),
        children: [
          if (widget.offline) CacheNotice(syncedAt: widget.syncedAt, onRetry: () => ref.read(profileProvider.notifier).refresh()),
          Row(children: [
            Stack(children: [
              UserAvatar(initials: u.initials, photoBase64: u.photoBase64, size: 88),
              Positioned(
                right: -4,
                bottom: -4,
                child: IconButton.filled(
                  tooltip: 'Change profile photo',
                  onPressed: _pickPhoto,
                  iconSize: 18,
                  style: IconButton.styleFrom(minimumSize: const Size(36, 36), backgroundColor: context.colors.onSurface, foregroundColor: context.colors.surface),
                  icon: const Icon(Icons.photo_camera_outlined),
                ),
              ),
            ]),
            const SizedBox(width: 18),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(u.fullName, style: context.text.headlineSmall),
                if (u.headline.isNotEmpty) ...[const SizedBox(height: 2), Text(u.headline, style: context.text.bodyLarge)],
                const SizedBox(height: 4),
                Row(children: [
                  Icon(Icons.place_outlined, size: 16, color: muted),
                  const SizedBox(width: 4),
                  Flexible(child: Text(u.location.isEmpty ? 'Add your location' : '${u.location}, Sierra Leone', style: context.text.bodySmall?.copyWith(color: muted))),
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: () => _edit('basics'),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Edit profile'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
            ),
          ),
          const SizedBox(height: 20),
          _CompletionCard(user: u, onEdit: _edit),
          _Section(
            title: 'About',
            onEdit: () => _edit('about'),
            child: u.about.isEmpty
                ? _Placeholder('Tell employers about yourself, your strengths and what you\'re looking for.', onTap: () => _edit('about'))
                : Text(u.about, style: context.text.bodyLarge),
          ),
          _Section(
            title: 'CV / resume',
            child: Column(children: [
              if (u.resume != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.picture_as_pdf_outlined, color: AppColors.danger),
                    title: Text(u.resume!.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text('${u.resume!.format.label} · ${Fmt.fileSize(u.resume!.sizeBytes)} · Updated ${Fmt.dateShort(u.resume!.uploadedAt)}'),
                    trailing: const Icon(Icons.visibility_outlined),
                    onTap: () => viewDocument(context,
                        title: 'Your CV',
                        fileName: u.resume!.fileName,
                        format: u.resume!.format,
                        storagePath: u.resume!.storagePath,
                        loadUrl: ref.read(backendProvider).documentUrl),
                  ),
                ),
              if (u.resume?.storagePath != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: TextButton.icon(
                    onPressed: _uploadingCv ? null : () => _fillFromCv(u, u.resume!.storagePath),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                    label: const Text('Fill my profile from my CV'),
                  ),
                ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _uploadingCv ? null : _uploadCv,
                  icon: _uploadingCv
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.upload_file_rounded),
                  label: Text(_uploadingCv ? 'Uploading…' : (u.resume == null ? 'Upload CV (PDF, DOC, DOCX)' : 'Replace CV')),
                ),
              ),
            ]),
          ),
          _Section(
            title: 'Experience',
            onEdit: () => _edit('experience'),
            child: u.experience.isEmpty
                ? _Placeholder('Add your work history.', onTap: () => _edit('experience'))
                : Column(children: [
                    for (final e in u.experience)
                      _TimelineItem(
                        icon: Icons.work_outline_rounded,
                        title: e.title,
                        subtitle: '${e.company} · ${e.location}',
                        meta: '${Fmt.monthYear(e.start)} – ${e.end == null ? 'Present' : Fmt.monthYear(e.end!)}',
                        body: e.description,
                      ),
                  ]),
          ),
          _Section(
            title: 'Education',
            onEdit: () => _edit('education'),
            child: u.education.isEmpty
                ? _Placeholder('Add your schools and qualifications.', onTap: () => _edit('education'))
                : Column(children: [
                    for (final e in u.education)
                      _TimelineItem(
                        icon: Icons.school_outlined,
                        title: e.school,
                        subtitle: '${e.degree}, ${e.field}',
                        meta: '${e.startYear} – ${e.endYear ?? 'Present'}',
                      ),
                  ]),
          ),
          _Section(
            title: 'Skills',
            onEdit: () => _edit('skills'),
            child: u.skills.isEmpty
                ? _Placeholder('Add skills so we can match you with the right jobs.', onTap: () => _edit('skills'))
                : Wrap(spacing: 8, runSpacing: 8, children: [for (final s in u.skills) TagChip(s)]),
          ),
          _Section(
            title: 'Certifications',
            onEdit: () => _edit('certifications'),
            child: u.certifications.isEmpty
                ? _Placeholder('Add licences and certificates.', onTap: () => _edit('certifications'))
                : Column(children: [
                    for (final c in u.certifications)
                      _TimelineItem(icon: Icons.workspace_premium_outlined, title: c.name, subtitle: c.issuer, meta: '${c.year}'),
                  ]),
          ),
          _Section(
            title: 'Languages',
            onEdit: () => _edit('languages'),
            child: u.languages.isEmpty
                ? _Placeholder('Add languages you speak, such as Krio, Mende or Temne.', onTap: () => _edit('languages'))
                : Wrap(spacing: 8, runSpacing: 8, children: [for (final l in u.languages) TagChip('${l.name} · ${l.level}', icon: Icons.translate_rounded)]),
          ),
          _Section(
            title: 'Links',
            onEdit: () => _edit('links'),
            child: u.portfolioUrl.isEmpty && u.linkedinUrl.isEmpty
                ? _Placeholder('Add your portfolio and LinkedIn.', onTap: () => _edit('links'))
                : Column(children: [
                    if (u.linkedinUrl.isNotEmpty) InfoRow(icon: Icons.link_rounded, label: 'LinkedIn', value: u.linkedinUrl),
                    if (u.portfolioUrl.isNotEmpty) InfoRow(icon: Icons.language_rounded, label: 'Portfolio', value: u.portfolioUrl),
                  ]),
          ),
          _Section(
            title: 'Job preferences',
            onEdit: () => _edit('preferences'),
            child: prefs.isEmpty
                ? _Placeholder('Tell us what you\'re looking for to get better recommendations.', onTap: () => _edit('preferences'))
                : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (prefs.titles.isNotEmpty) _PrefRow('Job titles', prefs.titles.join(', ')),
                    if (prefs.industries.isNotEmpty) _PrefRow('Industries', prefs.industries.map((e) => e.label).join(', ')),
                    if (prefs.locations.isNotEmpty) _PrefRow('Locations', prefs.locations.join(', ')),
                    if (prefs.workModes.isNotEmpty) _PrefRow('Work mode', prefs.workModes.map((e) => e.label).join(', ')),
                    if (prefs.employmentTypes.isNotEmpty) _PrefRow('Employment type', prefs.employmentTypes.map((e) => e.label).join(', ')),
                    if (prefs.salaryExpectation != null) _PrefRow('Salary expectation', 'SLE ${Fmt.money(prefs.salaryExpectation!)} / month'),
                  ]),
          ),
        ],
      ),
    );
  }
}

class _CompletionCard extends StatelessWidget {
  const _CompletionCard({required this.user, required this.onEdit});
  final AppUser user;
  final void Function(String) onEdit;

  static const _sections = {
    'Profile photo': 'basics',
    'Headline': 'basics',
    'Location': 'basics',
    'Phone number': 'basics',
    'About you': 'about',
    'Work experience': 'experience',
    'Education': 'education',
    'At least 5 skills': 'skills',
    'CV uploaded': 'basics',
    'Languages': 'languages',
    'Job preferences': 'preferences',
  };

  @override
  Widget build(BuildContext context) {
    final pct = user.completion;
    final missing = user.completionChecklist.where((i) => !i.done).toList();
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: context.palette.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Semantics(
            label: 'Profile $pct percent complete',
            excludeSemantics: true,
            child: SizedBox(
              width: 64,
              height: 64,
              child: Stack(alignment: Alignment.center, children: [
                SizedBox.expand(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: pct / 100),
                    duration: const Duration(milliseconds: 800),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, _) => CircularProgressIndicator(value: v, strokeWidth: 6, backgroundColor: context.palette.border, strokeCap: StrokeCap.round),
                  ),
                ),
                Text('$pct%', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(pct >= 100 ? 'All-star profile' : (pct >= 70 ? 'Strong profile' : 'Complete your profile'), style: context.text.titleMedium),
              const SizedBox(height: 2),
              Text(
                pct >= 100 ? 'Employers see your full profile.' : 'Complete profiles get more responses from employers.',
                style: context.text.bodySmall?.copyWith(color: context.palette.muted),
              ),
            ]),
          ),
        ]),
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 14),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in missing.take(4))
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 16),
                label: Text(m.label),
                onPressed: () => onEdit(_sections[m.label] ?? 'basics'),
              ),
          ]),
        ],
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.onEdit});
  final String title;
  final Widget child;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Divider(),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Semantics(header: true, child: Text(title, style: context.text.titleLarge))),
            if (onEdit != null) IconButton(tooltip: 'Edit $title', onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 20)),
          ]),
          const SizedBox(height: 8),
          child,
        ]),
      );
}

class _Placeholder extends StatelessWidget {
  const _Placeholder(this.text, {required this.onTap});
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            Icon(Icons.add_circle_outline_rounded, color: context.colors.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: context.text.bodyMedium?.copyWith(color: context.palette.muted))),
          ]),
        ),
      );
}

class _TimelineItem extends StatelessWidget {
  const _TimelineItem({required this.icon, required this.title, required this.subtitle, required this.meta, this.body});
  final IconData icon;
  final String title;
  final String subtitle;
  final String meta;
  final String? body;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text(subtitle, style: context.text.bodyMedium),
              Text(meta, style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
              if (body != null && body!.isNotEmpty) ...[const SizedBox(height: 4), Text(body!, style: context.text.bodyMedium)],
            ]),
          ),
        ]),
      );
}

class _PrefRow extends StatelessWidget {
  const _PrefRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: context.text.labelMedium?.copyWith(color: context.palette.muted)),
          Text(value, style: context.text.bodyLarge),
        ]),
      );
}
