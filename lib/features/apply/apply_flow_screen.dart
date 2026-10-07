import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/core_providers.dart';
import '../../providers/job_providers.dart';
import '../../providers/session_providers.dart';
import '../../providers/user_data_providers.dart';
import '../../services/file_service.dart';
import '../../widgets/common.dart';
import '../../widgets/company_logo.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';

enum _Step {
  personal('Personal info', Icons.person_outline_rounded),
  cv('CV / resume', Icons.description_outlined),
  cover('Cover letter', Icons.edit_note_rounded),
  note('Note', Icons.chat_bubble_outline_rounded),
  review('Review', Icons.fact_check_outlined);

  const _Step(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum _CoverMode { upload, write, skip }

class ApplyFlowScreen extends ConsumerWidget {
  const ApplyFlowScreen({super.key, required this.jobId});
  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final job = ref.watch(jobDetailProvider(jobId));
    final profile = ref.watch(profileProvider);
    final existing = ref.watch(applicationForJobProvider(jobId));

    if (job.hasError || profile.hasError) {
      return Scaffold(
        appBar: AppBar(title: const Text('Apply')),
        body: ErrorState(
          error: job.error ?? profile.error!,
          onRetry: () {
            ref.invalidate(jobDetailProvider(jobId));
            ref.invalidate(profileProvider);
          },
        ),
      );
    }
    if (!job.hasValue || !profile.hasValue) {
      return Scaffold(appBar: AppBar(title: const Text('Apply')), body: const SingleChildScrollView(child: ProfileSkeleton()));
    }
    if (existing != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Apply')),
        body: EmptyState(
          icon: Icons.task_alt_rounded,
          title: 'You\'ve already applied',
          message: 'Your application for ${job.value!.data.title} is ${existing.status.label.toLowerCase()}.',
          action: 'View application',
          onAction: () => context.pushReplacement('/application/${existing.id}'),
        ),
      );
    }
    return _ApplyFlow(job: job.value!.data, user: profile.value!.data);
  }
}

class _ApplyFlow extends ConsumerStatefulWidget {
  const _ApplyFlow({required this.job, required this.user});
  final Job job;
  final AppUser user;

  @override
  ConsumerState<_ApplyFlow> createState() => _ApplyFlowState();
}

class _ApplyFlowState extends ConsumerState<_ApplyFlow> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.user.fullName);
  late final _email = TextEditingController(text: widget.user.email);
  late final _phone = TextEditingController(text: widget.user.phone);
  late String _location = sierraLeoneLocations.contains(widget.user.location) ? widget.user.location : sierraLeoneLocations.first;
  final _coverText = TextEditingController();
  final _note = TextEditingController();

  _Step _step = _Step.personal;
  Resume? _resume;
  bool _saveCvToProfile = true;
  bool _uploading = false;
  _CoverMode _coverMode = _CoverMode.write;
  CoverLetter? _coverFile;
  bool _confirmed = false;
  bool _submitting = false;
  String? _stepError;

  @override
  void initState() {
    super.initState();
    _resume = widget.user.resume;
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _coverText, _note]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _dirty => _step.index > 0 || _coverText.text.isNotEmpty || _note.text.isNotEmpty;

  // ---- Navigation ------------------------------------------------------------

  bool _validateStep() {
    setState(() => _stepError = null);
    switch (_step) {
      case _Step.personal:
        return _formKey.currentState?.validate() ?? false;
      case _Step.cv:
        if (_resume == null) {
          setState(() => _stepError = 'Upload your CV to continue.');
          return false;
        }
      case _Step.cover:
        if (_coverMode == _CoverMode.upload && _coverFile == null) {
          setState(() => _stepError = 'Upload a cover letter, write one, or choose Skip.');
          return false;
        }
        if (_coverMode == _CoverMode.write && _coverText.text.trim().length < 50) {
          setState(() => _stepError = 'Write at least 50 characters, or choose Skip.');
          return false;
        }
      case _Step.note:
      case _Step.review:
        break;
    }
    return true;
  }

  void _next() {
    if (!_validateStep()) return;
    FocusScope.of(context).unfocus();
    if (_step == _Step.review) {
      _submit();
    } else {
      setState(() => _step = _Step.values[_step.index + 1]);
    }
  }

  void _back() {
    if (_step.index == 0) {
      _maybeLeave();
    } else {
      setState(() {
        _stepError = null;
        _step = _Step.values[_step.index - 1];
      });
    }
  }

  void _goTo(_Step s) => setState(() {
        _stepError = null;
        _step = s;
      });

  Future<void> _maybeLeave() async {
    if (!_dirty) {
      context.pop();
      return;
    }
    final leave = await confirmDialog(context,
        title: 'Discard application?', message: 'Your answers will not be saved.', confirmLabel: 'Discard', destructive: true);
    if (leave && mounted) context.pop();
  }

  // ---- Uploads ---------------------------------------------------------------

  Future<(PickedFile, String)?> _pickAndUpload() async {
    final files = ref.read(fileServiceProvider);
    try {
      final picked = await files.pickDocument();
      if (picked == null) return null;
      setState(() => _uploading = true);
      final path = await ref.read(userRepositoryProvider).uploadDocument(widget.user.id, picked.name, picked.bytes);
      return (picked, path);
    } on NetworkException {
      if (mounted) showSnack(context, 'You\'re offline. Connect to upload a file, or use the CV saved on your profile.', error: true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
    return null;
  }

  Future<void> _uploadCv() async {
    final r = await _pickAndUpload();
    if (r == null) return;
    setState(() {
      _stepError = null;
      _resume = Resume(
        id: const Uuid().v4(),
        fileName: r.$1.name,
        sizeBytes: r.$1.size,
        uploadedAt: DateTime.now(),
        format: r.$1.format!,
        storagePath: r.$2,
      );
    });
  }

  Future<void> _uploadCover() async {
    final r = await _pickAndUpload();
    if (r == null) return;
    setState(() {
      _stepError = null;
      _coverFile = CoverLetter(
        id: const Uuid().v4(),
        kind: CoverLetterKind.uploaded,
        fileName: r.$1.name,
        sizeBytes: r.$1.size,
        format: r.$1.format,
        storagePath: r.$2,
      );
    });
  }

  void _useTemplate() {
    final u = widget.user;
    final j = widget.job;
    final topSkills = j.skills.where((s) => u.skills.map((e) => e.toLowerCase()).contains(s.toLowerCase())).take(3).toList();
    final current = u.experience.isNotEmpty ? u.experience.first : null;
    _coverText.text = 'Dear Hiring Manager,\n\n'
        'I am writing to apply for the ${j.title} position at ${j.companyName}. '
        '${current != null ? 'In my current role as ${current.title} at ${current.company}, I ' : 'I '}'
        'have developed experience that matches what you are looking for'
        '${topSkills.isNotEmpty ? ', including ${topSkills.join(', ')}' : ''}.\n\n'
        '[Add one or two examples of results you achieved that are relevant to this role.]\n\n'
        'I would welcome the chance to discuss how I can contribute to your team in ${j.location}. '
        'Thank you for considering my application.\n\n'
        'Yours sincerely,\n${_name.text}';
    setState(() => _stepError = null);
  }

  // ---- Submit ----------------------------------------------------------------

  CoverLetter? get _coverLetter => switch (_coverMode) {
        _CoverMode.upload => _coverFile,
        _CoverMode.write => CoverLetter(id: const Uuid().v4(), kind: CoverLetterKind.written, text: _coverText.text.trim()),
        _CoverMode.skip => null,
      };

  Future<void> _submit() async {
    if (!_confirmed) {
      setState(() => _stepError = 'Confirm that your information is accurate.');
      return;
    }
    setState(() => _submitting = true);
    final now = DateTime.now();
    final app = JobApplication(
      id: const Uuid().v4(),
      jobId: widget.job.id,
      userId: widget.user.id,
      status: ApplicationStatus.applied,
      submittedAt: now,
      history: [StatusEvent(status: ApplicationStatus.applied, at: now)],
      applicant: ApplicantInfo(fullName: _name.text.trim(), email: _email.text.trim(), phone: _phone.text.trim(), location: _location),
      resume: _resume!,
      coverLetter: _coverLetter,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      job: widget.job,
    );
    try {
      final saved = await ref.read(applicationsProvider.notifier).submit(app);
      // Keep the profile up to date with details entered here.
      final u = widget.user;
      final updated = u.copyWith(
        phone: u.phone.isEmpty ? _phone.text.trim() : null,
        location: u.location.isEmpty ? _location : null,
        resume: _saveCvToProfile && _resume?.id != u.resume?.id ? () => _resume : null,
      );
      if (updated.toJson().toString() != u.toJson().toString()) {
        await ref.read(profileProvider.notifier).save(updated);
      }
      if (mounted) context.pushReplacement('/applied/${saved.id}');
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        showError(context, e);
      }
    }
  }

  // ---- UI --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(tooltip: 'Close', icon: const Icon(Icons.close_rounded), onPressed: _maybeLeave),
          title: Text('Apply · ${widget.job.companyName}', overflow: TextOverflow.ellipsis),
        ),
        body: Column(children: [
          _StepHeader(current: _step),
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: AppSpacing.maxReadingWidth),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, a) => FadeTransition(
                    opacity: a,
                    child: SlideTransition(position: Tween(begin: const Offset(0.03, 0), end: Offset.zero).animate(a), child: child),
                  ),
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 20, AppSpacing.gutter, 24),
                      children: [
                        _JobSummary(job: widget.job),
                        const SizedBox(height: 24),
                        switch (_step) {
                          _Step.personal => _personal(),
                          _Step.cv => _cv(),
                          _Step.cover => _cover(),
                          _Step.note => _noteStep(),
                          _Step.review => _review(),
                        },
                        if (_stepError != null) ...[
                          const SizedBox(height: 16),
                          Semantics(
                            liveRegion: true,
                            child: Row(children: [
                              const Icon(Icons.error_outline_rounded, color: AppColors.danger, size: 20),
                              const SizedBox(width: 8),
                              Expanded(child: Text(_stepError!, style: context.text.bodyMedium?.copyWith(color: AppColors.danger))),
                            ]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ]),
        bottomNavigationBar: _BottomBar(
          step: _step,
          busy: _submitting || _uploading,
          onBack: _back,
          onNext: _next,
        ),
      ),
    );
  }

  Widget _title(String title, String subtitle) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Semantics(header: true, child: Text(title, style: context.text.headlineSmall)),
          const SizedBox(height: 6),
          Text(subtitle, style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
        ]),
      );

  Widget _personal() => Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _title('Confirm your details', 'We\'ve filled these in from your profile. The employer will use them to contact you.'),
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.name],
            decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline_rounded)),
            validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your full name' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.mail_outline_rounded)),
            validator: (v) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch((v ?? '').trim()) ? null : 'Enter a valid email address',
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            autofillHints: const [AutofillHints.telephoneNumber],
            decoration: const InputDecoration(labelText: 'Phone number', hintText: '+232 76 000 000', prefixIcon: Icon(Icons.phone_outlined)),
            validator: (v) => (v ?? '').replaceAll(RegExp(r'[^0-9]'), '').length < 8 ? 'Enter a phone number the employer can call' : null,
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _location,
            decoration: const InputDecoration(labelText: 'Where you live', prefixIcon: Icon(Icons.place_outlined)),
            items: [for (final l in sierraLeoneLocations) DropdownMenuItem(value: l, child: Text(l))],
            onChanged: (v) => setState(() => _location = v ?? _location),
          ),
        ]),
      );

  Widget _cv() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('Your CV', 'Upload a PDF, DOC or DOCX file up to 5 MB.'),
        if (_resume != null)
          _DocumentTile(
            icon: Icons.picture_as_pdf_outlined,
            name: _resume!.fileName,
            detail: '${_resume!.format.label} · ${Fmt.fileSize(_resume!.sizeBytes)} · ${_resume!.id == widget.user.resume?.id ? 'From your profile' : 'Uploaded just now'}',
            onRemove: () => setState(() => _resume = null),
          ),
        const SizedBox(height: 12),
        _UploadBox(
          busy: _uploading,
          label: _resume == null ? 'Upload your CV' : 'Upload a different CV',
          onTap: _uploadCv,
        ),
        if (_resume != null && _resume!.id != widget.user.resume?.id) ...[
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: _saveCvToProfile,
            onChanged: (v) => setState(() => _saveCvToProfile = v ?? true),
            title: const Text('Save this CV to my profile for future applications'),
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ],
      ]);

  Widget _cover() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('Cover letter', 'A short letter explaining why you\'re a good fit can make your application stand out.'),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<_CoverMode>(
            segments: const [
              ButtonSegment(value: _CoverMode.write, label: Text('Write'), icon: Icon(Icons.edit_outlined)),
              ButtonSegment(value: _CoverMode.upload, label: Text('Upload'), icon: Icon(Icons.upload_file_rounded)),
              ButtonSegment(value: _CoverMode.skip, label: Text('Skip')),
            ],
            selected: {_coverMode},
            showSelectedIcon: false,
            onSelectionChanged: (s) => setState(() {
              _coverMode = s.first;
              _stepError = null;
            }),
          ),
        ),
        const SizedBox(height: 20),
        switch (_coverMode) {
          _CoverMode.write => Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              TextField(
                controller: _coverText,
                minLines: 10,
                maxLines: 18,
                maxLength: 3000,
                textCapitalization: TextCapitalization.sentences,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Dear Hiring Manager,', alignLabelWithHint: true),
              ),
              TextButton.icon(onPressed: _useTemplate, icon: const Icon(Icons.auto_awesome_outlined, size: 18), label: const Text('Start from a template')),
            ]),
          _CoverMode.upload => Column(children: [
              if (_coverFile != null) ...[
                _DocumentTile(
                  icon: Icons.description_outlined,
                  name: _coverFile!.fileName ?? 'Cover letter',
                  detail: '${_coverFile!.format?.label ?? ''} · ${Fmt.fileSize(_coverFile!.sizeBytes ?? 0)}',
                  onRemove: () => setState(() => _coverFile = null),
                ),
                const SizedBox(height: 12),
              ],
              _UploadBox(busy: _uploading, label: _coverFile == null ? 'Upload cover letter' : 'Replace file', onTap: _uploadCover),
            ]),
          _CoverMode.skip => Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(AppSpacing.radius)),
              child: Row(children: [
                Icon(Icons.info_outline_rounded, color: context.palette.muted),
                const SizedBox(width: 12),
                const Expanded(child: Text('You can apply without a cover letter, but many employers in Sierra Leone expect one.')),
              ]),
            ),
        },
      ]);

  Widget _noteStep() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _title('Message to the employer', 'Optional. Mention your availability, notice period or anything else they should know.'),
        TextField(
          controller: _note,
          minLines: 4,
          maxLines: 8,
          maxLength: 500,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. I can start within two weeks and I\'m happy to relocate.'),
        ),
      ]);

  Widget _review() {
    final cover = _coverLetter;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _title('Review your application', 'Check everything before you send it. You can\'t edit an application after submitting.'),
      _ReviewCard(
        title: 'Personal info',
        onEdit: () => _goTo(_Step.personal),
        children: [
          Text(_name.text, style: context.text.titleSmall),
          Text(_email.text),
          Text(_phone.text),
          Text('$_location, Sierra Leone'),
        ],
      ),
      _ReviewCard(
        title: 'CV',
        onEdit: () => _goTo(_Step.cv),
        children: [Text(_resume?.fileName ?? 'Missing', style: context.text.titleSmall), if (_resume != null) Text('${_resume!.format.label} · ${Fmt.fileSize(_resume!.sizeBytes)}')],
      ),
      _ReviewCard(
        title: 'Cover letter',
        onEdit: () => _goTo(_Step.cover),
        children: [
          if (cover == null) const Text('Not included'),
          if (cover?.kind == CoverLetterKind.uploaded) Text(cover!.fileName ?? '', style: context.text.titleSmall),
          if (cover?.kind == CoverLetterKind.written) Text(cover!.text ?? '', maxLines: 5, overflow: TextOverflow.ellipsis),
        ],
      ),
      _ReviewCard(
        title: 'Message to employer',
        onEdit: () => _goTo(_Step.note),
        children: [Text(_note.text.trim().isEmpty ? 'No message' : _note.text.trim())],
      ),
      const SizedBox(height: 8),
      CheckboxListTile(
        contentPadding: EdgeInsets.zero,
        value: _confirmed,
        onChanged: (v) => setState(() {
          _confirmed = v ?? false;
          _stepError = null;
        }),
        controlAffinity: ListTileControlAffinity.leading,
        title: const Text('I confirm this information is accurate and I agree to share it with the employer.'),
      ),
      if (!ref.watch(onlineProvider))
        Container(
          margin: const EdgeInsets.only(top: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.warning.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: const Row(children: [
            Icon(Icons.wifi_off_rounded, color: AppColors.warning),
            SizedBox(width: 10),
            Expanded(child: Text('You\'re offline. We\'ll save your application and send it as soon as you reconnect.')),
          ]),
        ),
    ]);
  }
}

class _StepHeader extends StatelessWidget {
  const _StepHeader({required this.current});
  final _Step current;

  @override
  Widget build(BuildContext context) {
    final i = current.index;
    return Semantics(
      label: 'Step ${i + 1} of ${_Step.values.length}: ${current.label}',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 4, AppSpacing.gutter, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            for (var s = 0; s < _Step.values.length; s++) ...[
              if (s > 0) const SizedBox(width: 6),
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  height: 4,
                  decoration: BoxDecoration(
                    color: s <= i ? context.colors.primary : context.palette.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ]),
          const SizedBox(height: 8),
          Text('Step ${i + 1} of ${_Step.values.length} · ${current.label}', style: context.text.labelMedium?.copyWith(color: context.palette.muted)),
        ]),
      ),
    );
  }
}

class _JobSummary extends StatelessWidget {
  const _JobSummary({required this.job});
  final Job job;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(AppSpacing.radius)),
        child: Row(children: [
          CompanyLogo(company: job.company, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(job.title, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${job.companyName} · ${job.location}', style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
            ]),
          ),
        ]),
      );
}

class _UploadBox extends StatelessWidget {
  const _UploadBox({required this.busy, required this.label, required this.onTap});
  final bool busy;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: busy ? 'Uploading' : label,
        excludeSemantics: true,
        child: InkWell(
          onTap: busy ? null : onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              border: Border.all(color: context.colors.primary.withValues(alpha: 0.5), width: 1.5),
              color: context.palette.accentTint,
            ),
            child: Column(children: [
              if (busy) ...[
                const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.6)),
                const SizedBox(height: 12),
                Text('Uploading…', style: context.text.titleSmall),
              ] else ...[
                Icon(Icons.cloud_upload_outlined, size: 34, color: context.colors.primary),
                const SizedBox(height: 10),
                Text(label, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text('PDF, DOC or DOCX · max 5 MB', style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
              ],
            ]),
          ),
        ),
      );
}

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({required this.icon, required this.name, required this.detail, required this.onRemove});
  final IconData icon;
  final String name;
  final String detail;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.danger.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: AppColors.danger),
          ),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.text.titleSmall),
          subtitle: Text(detail),
          trailing: IconButton(tooltip: 'Remove', onPressed: onRemove, icon: const Icon(Icons.close_rounded)),
        ),
      );
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.title, required this.onEdit, required this.children});
  final String title;
  final VoidCallback onEdit;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(title, style: context.text.labelLarge?.copyWith(color: context.palette.muted))),
                TextButton(onPressed: onEdit, child: Text('Edit', semanticsLabel: 'Edit $title')),
              ]),
              ...children.map((c) => Padding(padding: const EdgeInsets.only(bottom: 2), child: c)),
            ]),
          ),
        ),
      );
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.step, required this.busy, required this.onBack, required this.onNext});
  final _Step step;
  final bool busy;
  final VoidCallback onBack;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final last = step == _Step.review;
    final optional = step == _Step.note;
    return DecoratedBox(
      decoration: BoxDecoration(color: context.colors.surface, border: Border(top: BorderSide(color: context.palette.border))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 12, AppSpacing.gutter, 12),
          child: Row(children: [
            if (step.index > 0)
              TextButton(
                onPressed: busy ? null : onBack,
                style: TextButton.styleFrom(foregroundColor: context.colors.onSurface),
                child: const Text('Back', style: TextStyle(decoration: TextDecoration.underline)),
              ),
            const Spacer(),
            SizedBox(
              width: 200,
              child: PrimaryButton(
                label: last ? 'Submit application' : (optional ? 'Continue' : 'Next'),
                icon: last ? Icons.send_rounded : null,
                loading: busy && last,
                onPressed: busy ? null : onNext,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
