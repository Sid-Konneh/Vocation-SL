import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/models.dart';
import '../../../widgets/common.dart';
import '../../providers.dart';
import '../../widgets.dart';

/// Create or edit a job. Lists (responsibilities, skills…) are entered one per line.
class JobEditorScreen extends ConsumerStatefulWidget {
  const JobEditorScreen({super.key, this.jobId});
  final String? jobId;

  @override
  ConsumerState<JobEditorScreen> createState() => _JobEditorScreenState();
}

class _JobEditorScreenState extends ConsumerState<JobEditorScreen> {
  final _form = GlobalKey<FormState>();
  Job? _original;
  bool _loaded = false;
  bool _saving = false;

  final _title = TextEditingController();
  final _about = TextEditingController();
  final _description = TextEditingController();
  final _responsibilities = TextEditingController();
  final _requirements = TextEditingController();
  final _preferred = TextEditingController();
  final _skills = TextEditingController();
  final _benefits = TextEditingController();
  final _salaryMin = TextEditingController();
  final _salaryMax = TextEditingController();
  String _location = 'Freetown';
  EmploymentType _type = EmploymentType.fullTime;
  WorkMode _mode = WorkMode.onsite;
  Industry _industry = Industry.technology;
  ExperienceLevel _level = ExperienceLevel.mid;
  DateTime _deadline = DateTime.now().add(const Duration(days: 21));

  @override
  void dispose() {
    for (final c in [_title, _about, _description, _responsibilities, _requirements, _preferred, _skills, _benefits, _salaryMin, _salaryMax]) {
      c.dispose();
    }
    super.dispose();
  }

  void _load(Company company, List<Job> jobs) {
    if (_loaded) return;
    _loaded = true;
    _industry = company.industry;
    _location = sierraLeoneLocations.contains(company.location) ? company.location : 'Freetown';
    if (widget.jobId == null) return;
    final j = jobs.where((x) => x.id == widget.jobId).firstOrNull;
    if (j == null) return;
    _original = j;
    _title.text = j.title;
    _about.text = j.about;
    _description.text = j.description;
    _responsibilities.text = j.responsibilities.join('\n');
    _requirements.text = j.requirements.join('\n');
    _preferred.text = j.preferred.join('\n');
    _skills.text = j.skills.join('\n');
    _benefits.text = j.benefits.join('\n');
    _salaryMin.text = j.salaryMin?.toString() ?? '';
    _salaryMax.text = j.salaryMax?.toString() ?? '';
    _location = sierraLeoneLocations.contains(j.location) ? j.location : _location;
    _type = j.employmentType;
    _mode = j.workMode;
    _industry = j.industry;
    _level = j.experienceLevel;
    _deadline = j.deadline;
  }

  /// Already submitted, live or closed (declined jobs are edited and resubmitted).
  bool get _posted => _original != null && const {JobStatus.pending, JobStatus.published, JobStatus.closed}.contains(_original!.status);
  bool get _declined => _original?.status == JobStatus.declined;
  bool get _rejected => _original?.status == JobStatus.rejected;

  List<String> _lines(TextEditingController c) =>
      c.text.split('\n').map((l) => l.replaceFirst(RegExp(r'^\s*[-•*]\s*'), '').trim()).where((l) => l.isNotEmpty).toList();

  Job _build(Company company) => Job(
        id: _original?.id ?? '',
        title: _title.text.trim(),
        companyId: company.id,
        location: _location,
        employmentType: _type,
        workMode: _mode,
        industry: _industry,
        experienceLevel: _level,
        salaryMin: int.tryParse(_salaryMin.text.replaceAll(',', '').trim()),
        salaryMax: int.tryParse(_salaryMax.text.replaceAll(',', '').trim()),
        postedAt: _original?.postedAt ?? DateTime.now(),
        deadline: DateTime(_deadline.year, _deadline.month, _deadline.day, 23, 59),
        about: _about.text.trim(),
        description: _description.text.trim(),
        responsibilities: _lines(_responsibilities),
        requirements: _lines(_requirements),
        preferred: _lines(_preferred),
        skills: _lines(_skills),
        benefits: _lines(_benefits),
        status: _original?.status ?? JobStatus.draft,
      );

  Future<void> _save(Company company, {required bool post}) async {
    if (post && !(_form.currentState?.validate() ?? false)) {
      showSnack(context, 'Fill in the highlighted fields before posting.', error: true);
      return;
    }
    if (!post && _title.text.trim().isEmpty) {
      showSnack(context, 'Give the draft a job title first.', error: true);
      return;
    }
    if (post && !_posted && !company.isApproved) {
      final ok = await confirmDialog(
        context,
        title: 'Submit this job?',
        message: 'Your company is awaiting approval. The job will be saved as "Awaiting approval" and reviewed once your company is approved.',
        confirmLabel: 'Submit job',
      );
      if (!ok) return;
    }
    setState(() => _saving = true);
    try {
      final status = post ? (_posted ? _original!.status : JobStatus.published) : JobStatus.draft;
      final saved = await ref.read(employerJobsProvider.notifier).save(_build(company), status: status);
      if (!mounted) return;
      showSnack(
        context,
        !post
            ? 'Draft saved'
            : _posted
                ? 'Job updated'
                : saved.status == JobStatus.pending
                    ? 'Job submitted for review. It goes live once Vocation SL approves it.'
                    : 'Job posted and live',
      );
      context.pop();
    } on NetworkException {
      if (mounted) showSnack(context, 'You\'re offline. Connect to save this job.', error: true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final company = ref.watch(companyProvider).value?.data;
    final jobs = ref.watch(employerJobsProvider).value?.data ?? const <Job>[];
    if (company == null) return const Scaffold(body: SizedBox());
    _load(company, jobs);

    Widget gap() => const SizedBox(height: 14);
    Widget section(String title, List<Widget> children) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: SectionCard(title: title, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children)),
        );
    String? req(String? v, String what) => (v ?? '').trim().isEmpty ? 'Enter $what' : null;
    Widget listField(TextEditingController c, String label, String hint, {bool required = false}) => TextFormField(
          controller: c,
          minLines: 3,
          maxLines: 10,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: label, hintText: hint, helperText: 'One item per line', alignLabelWithHint: true),
          validator: required ? (v) => _lines(c).isEmpty ? 'Add at least one item' : null : null,
        );

    return Scaffold(
      appBar: AppBar(
        title: Text(_original == null ? 'Post a job' : 'Edit job'),
        actions: [
          if (!_posted && !_rejected)
            TextButton(onPressed: _saving ? null : () => _save(company, post: false), child: const Text('Save draft')),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _saving || _rejected ? null : () => _save(company, post: true),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(_posted ? 'Save changes' : _declined ? 'Resubmit for review' : 'Post job'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ResponsiveCenter(
          maxWidth: 860,
          child: ListView(padding: const EdgeInsets.all(AppSpacing.gutter), children: [
            if (_declined || _rejected) _ReviewNotice(job: _original!),
            section('Basics', [
              TextFormField(
                controller: _title,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Job title *', hintText: 'e.g. Accounts Assistant'),
                validator: (v) => req(v, 'a job title'),
              ),
              gap(),
              Wrap(spacing: 12, runSpacing: 14, children: [
                _dropdown<String>('Location *', _location, sierraLeoneLocations, (v) => v, (v) => setState(() => _location = v)),
                _dropdown<EmploymentType>('Job type *', _type, EmploymentType.values, (v) => v.label, (v) => setState(() => _type = v)),
                _dropdown<WorkMode>('Work mode *', _mode, WorkMode.values, (v) => v.label, (v) => setState(() => _mode = v)),
                _dropdown<Industry>('Industry *', _industry, Industry.values, (v) => v.label, (v) => setState(() => _industry = v)),
                _dropdown<ExperienceLevel>('Experience *', _level, ExperienceLevel.values, (v) => v.label, (v) => setState(() => _level = v)),
                SizedBox(
                  width: 260,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.event_outlined),
                    label: Text('Deadline: ${Fmt.date(_deadline)}'),
                    onPressed: () async {
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _deadline.isBefore(DateTime.now()) ? DateTime.now().add(const Duration(days: 1)) : _deadline,
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 180)),
                      );
                      if (d != null) setState(() => _deadline = d);
                    },
                  ),
                ),
              ]),
            ]),
            section('Salary (monthly, SLE)', [
              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _salaryMin,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'From', prefixText: 'SLE '),
                    validator: (v) => (v ?? '').trim().isEmpty || int.tryParse(v!.replaceAll(',', '').trim()) != null ? null : 'Numbers only',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _salaryMax,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'To', prefixText: 'SLE '),
                    validator: (v) {
                      final t = (v ?? '').replaceAll(',', '').trim();
                      if (t.isEmpty) return null;
                      final max = int.tryParse(t);
                      final min = int.tryParse(_salaryMin.text.replaceAll(',', '').trim());
                      if (max == null) return 'Numbers only';
                      if (min != null && max < min) return 'Must be at least "From"';
                      return null;
                    },
                  ),
                ),
              ]),
              const SizedBox(height: 6),
              Text('Leave blank to show "Salary not disclosed". Jobs with a salary get more applicants.',
                  style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
            ]),
            section('Description', [
              TextFormField(
                controller: _about,
                maxLength: 200,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'About the job (one-line summary) *'),
                validator: (v) => req(v, 'a short summary'),
              ),
              TextFormField(
                controller: _description,
                minLines: 5,
                maxLines: 14,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Full description *', alignLabelWithHint: true),
                validator: (v) => (v ?? '').trim().length < 80 ? 'Write at least 80 characters' : null,
              ),
            ]),
            section('Details', [
              listField(_responsibilities, 'Responsibilities *', 'Manage the branch network\nTrain new staff', required: true),
              gap(),
              listField(_requirements, 'Eligibility & requirements *', 'Degree in Accounting\n2+ years of experience', required: true),
              gap(),
              listField(_preferred, 'Preferred qualifications', 'ACCA part-qualified'),
              gap(),
              listField(_skills, 'Skills *', 'Excel\nQuickBooks', required: true),
              gap(),
              listField(_benefits, 'Benefits', 'NASSIT pension contributions\nMedical cover'),
            ]),
            const SizedBox(height: 40),
          ]),
        ),
      ),
    );
  }

  Widget _dropdown<T>(String label, T value, List<T> values, String Function(T) text, void Function(T) onChanged) => SizedBox(
        width: 260,
        child: DropdownButtonFormField<T>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [for (final v in values) DropdownMenuItem(value: v, child: Text(text(v), overflow: TextOverflow.ellipsis))],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      );
}

/// Explains why an admin declined or rejected the job.
class _ReviewNotice extends StatelessWidget {
  const _ReviewNotice({required this.job});
  final Job job;

  @override
  Widget build(BuildContext context) {
    final rejected = job.status == JobStatus.rejected;
    final color = rejected ? AppColors.danger : AppColors.warning;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppSpacing.radius)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(rejected ? Icons.block_outlined : Icons.edit_note_rounded, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(rejected ? 'This job was rejected' : 'Changes needed before this job can go live', style: context.text.titleSmall),
              if (job.reviewNote.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(job.reviewNote, style: context.text.bodyMedium)),
              const SizedBox(height: 4),
              Text(
                rejected
                    ? 'Rejected jobs can\'t be resubmitted. Contact support if you think this is a mistake.'
                    : 'Make the changes below, then tap "Resubmit for review".',
                style: context.text.bodySmall,
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}