import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/session_providers.dart';
import '../../widgets/common.dart';
import '../../widgets/skeletons.dart';
import '../../widgets/states.dart';

const _titles = {
  'basics': 'Edit intro',
  'about': 'About',
  'experience': 'Experience',
  'education': 'Education',
  'skills': 'Skills',
  'certifications': 'Certifications',
  'languages': 'Languages',
  'links': 'Links',
  'preferences': 'Job preferences',
};

class EditProfileScreen extends ConsumerWidget {
  const EditProfileScreen({super.key, this.section});
  final String? section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(profileProvider);
    final s = _titles.containsKey(section) ? section! : 'basics';
    return async.when(
      loading: () => Scaffold(appBar: AppBar(title: Text(_titles[s]!)), body: const SingleChildScrollView(child: ProfileSkeleton())),
      error: (e, _) => Scaffold(appBar: AppBar(), body: ErrorState(error: e, onRetry: () => ref.invalidate(profileProvider))),
      data: (loaded) => _Editor(user: loaded.data, section: s),
    );
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({required this.user, required this.section});
  final AppUser user;
  final String section;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  final _form = GlobalKey<FormState>();
  late AppUser _draft = widget.user;
  bool _saving = false;

  late final _name = TextEditingController(text: widget.user.fullName);
  late final _headline = TextEditingController(text: widget.user.headline);
  late final _phone = TextEditingController(text: widget.user.phone);
  late final _about = TextEditingController(text: widget.user.about);
  late final _portfolio = TextEditingController(text: widget.user.portfolioUrl);
  late final _linkedin = TextEditingController(text: widget.user.linkedinUrl);
  late final _salary = TextEditingController(text: widget.user.preferences.salaryExpectation?.toString() ?? '');
  final _skill = TextEditingController();
  final _title = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _headline, _phone, _about, _portfolio, _linkedin, _salary, _skill, _title]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? true)) return;
    var u = _draft;
    switch (widget.section) {
      case 'basics':
        u = u.copyWith(fullName: _name.text.trim(), headline: _headline.text.trim(), phone: _phone.text.trim());
      case 'about':
        u = u.copyWith(about: _about.text.trim());
      case 'links':
        u = u.copyWith(portfolioUrl: _portfolio.text.trim(), linkedinUrl: _linkedin.text.trim());
      case 'preferences':
        final p = u.preferences;
        u = u.copyWith(
          preferences: JobPreferences(
            titles: p.titles,
            industries: p.industries,
            locations: p.locations,
            workModes: p.workModes,
            employmentTypes: p.employmentTypes,
            salaryExpectation: int.tryParse(_salary.text.replaceAll(',', '').trim()),
          ),
        );
    }
    setState(() => _saving = true);
    try {
      final synced = await ref.read(profileProvider.notifier).save(u);
      if (!mounted) return;
      showSnack(context, synced ? 'Profile updated' : 'Saved on this device. Will sync when you\'re online.');
      context.pop();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        showError(context, e);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[widget.section]!),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(minimumSize: const Size(80, 40)),
              child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'),
            ),
          ),
        ],
      ),
      body: Form(
        key: _form,
        child: ResponsiveCenter(
          maxWidth: AppSpacing.maxReadingWidth,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 16, AppSpacing.gutter, 40),
            children: switch (widget.section) {
              'basics' => _basics(),
              'about' => _aboutSection(),
              'experience' => _experience(),
              'education' => _education(),
              'skills' => _skills(),
              'certifications' => _certifications(),
              'languages' => _languages(),
              'links' => _links(),
              _ => _preferences(),
            },
          ),
        ),
      ),
    );
  }

  // ---- Sections --------------------------------------------------------------

  List<Widget> _basics() => [
        TextFormField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Full name'),
          validator: (v) => (v ?? '').trim().length < 2 ? 'Enter your full name' : null,
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _headline,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Headline', hintText: 'e.g. Registered Nurse · Maternity care'),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: 'Phone', hintText: '+232 76 000 000'),
        ),
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: sierraLeoneLocations.contains(_draft.location) ? _draft.location : null,
          decoration: const InputDecoration(labelText: 'Location'),
          items: [for (final l in sierraLeoneLocations) DropdownMenuItem(value: l, child: Text(l))],
          onChanged: (v) => setState(() => _draft = _draft.copyWith(location: v)),
        ),
        const SizedBox(height: 14),
        TextFormField(
          initialValue: _draft.email,
          enabled: false,
          decoration: const InputDecoration(labelText: 'Email (used to sign in)'),
        ),
      ];

  List<Widget> _aboutSection() => [
        Text('Summarise your experience, strengths and the kind of role you want.', style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
        const SizedBox(height: 14),
        TextFormField(
          controller: _about,
          minLines: 8,
          maxLines: 16,
          maxLength: 1500,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(alignLabelWithHint: true),
        ),
      ];

  List<Widget> _links() => [
        TextFormField(
          controller: _linkedin,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'LinkedIn', prefixIcon: Icon(Icons.link_rounded), hintText: 'linkedin.com/in/your-name'),
        ),
        const SizedBox(height: 14),
        TextFormField(
          controller: _portfolio,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(labelText: 'Portfolio or website', prefixIcon: Icon(Icons.language_rounded)),
        ),
      ];

  List<Widget> _experience() => [
        for (var i = 0; i < _draft.experience.length; i++)
          _ItemCard(
            title: _draft.experience[i].title,
            subtitle: '${_draft.experience[i].company} · ${Fmt.monthYear(_draft.experience[i].start)} – ${_draft.experience[i].end == null ? 'Present' : Fmt.monthYear(_draft.experience[i].end!)}',
            onEdit: () => _editExperience(i),
            onDelete: () => setState(() => _draft = _draft.copyWith(experience: [..._draft.experience]..removeAt(i))),
          ),
        _AddButton(label: 'Add experience', onTap: () => _editExperience(null)),
      ];

  List<Widget> _education() => [
        for (var i = 0; i < _draft.education.length; i++)
          _ItemCard(
            title: _draft.education[i].school,
            subtitle: '${_draft.education[i].degree}, ${_draft.education[i].field} · ${_draft.education[i].startYear}–${_draft.education[i].endYear ?? 'Present'}',
            onEdit: () => _editEducation(i),
            onDelete: () => setState(() => _draft = _draft.copyWith(education: [..._draft.education]..removeAt(i))),
          ),
        _AddButton(label: 'Add education', onTap: () => _editEducation(null)),
      ];

  List<Widget> _skills() {
    void add() {
      final s = _skill.text.trim();
      if (s.isEmpty || _draft.skills.any((x) => x.toLowerCase() == s.toLowerCase())) return;
      setState(() => _draft = _draft.copyWith(skills: [..._draft.skills, s]));
      _skill.clear();
    }

    return [
      TextField(
        controller: _skill,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (_) => add(),
        decoration: InputDecoration(
          labelText: 'Add a skill',
          hintText: 'e.g. Excel, Nursing, AutoCAD',
          suffixIcon: IconButton(tooltip: 'Add skill', onPressed: add, icon: const Icon(Icons.add_rounded)),
        ),
      ),
      const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in _draft.skills)
          InputChip(
            label: Text(s),
            onDeleted: () => setState(() => _draft = _draft.copyWith(skills: _draft.skills.where((x) => x != s).toList())),
            deleteButtonTooltipMessage: 'Remove $s',
          ),
      ]),
      const SizedBox(height: 16),
      Text('${_draft.skills.length} skills · add at least 5 for better matches', style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
    ];
  }

  List<Widget> _certifications() => [
        for (var i = 0; i < _draft.certifications.length; i++)
          _ItemCard(
            title: _draft.certifications[i].name,
            subtitle: '${_draft.certifications[i].issuer} · ${_draft.certifications[i].year}',
            onDelete: () => setState(() => _draft = _draft.copyWith(certifications: [..._draft.certifications]..removeAt(i))),
          ),
        _AddButton(
          label: 'Add certification',
          onTap: () async {
            final r = await _simpleForm('Add certification', ['Name', 'Issuing organisation', 'Year']);
            if (r == null) return;
            setState(() => _draft = _draft.copyWith(certifications: [
                  ..._draft.certifications,
                  Certification(name: r[0], issuer: r[1], year: int.tryParse(r[2]) ?? DateTime.now().year),
                ]));
          },
        ),
      ];

  List<Widget> _languages() => [
        for (var i = 0; i < _draft.languages.length; i++)
          _ItemCard(
            title: _draft.languages[i].name,
            subtitle: _draft.languages[i].level,
            onDelete: () => setState(() => _draft = _draft.copyWith(languages: [..._draft.languages]..removeAt(i))),
          ),
        _AddButton(
          label: 'Add language',
          onTap: () async {
            final r = await showDialog<LanguageSkill>(context: context, builder: (_) => const _LanguageDialog());
            if (r != null) setState(() => _draft = _draft.copyWith(languages: [..._draft.languages, r]));
          },
        ),
      ];

  List<Widget> _preferences() {
    final p = _draft.preferences;
    JobPreferences with_({List<String>? titles, Set<Industry>? industries, Set<String>? locations, Set<WorkMode>? modes, Set<EmploymentType>? types}) =>
        JobPreferences(
          titles: titles ?? p.titles,
          industries: industries ?? p.industries,
          locations: locations ?? p.locations,
          workModes: modes ?? p.workModes,
          employmentTypes: types ?? p.employmentTypes,
          salaryExpectation: p.salaryExpectation,
        );
    Set<T> flip<T>(Set<T> s, T v) => s.contains(v) ? ({...s}..remove(v)) : {...s, v};
    void addTitle() {
      final t = _title.text.trim();
      if (t.isEmpty) return;
      setState(() => _draft = _draft.copyWith(preferences: with_(titles: [...p.titles, t])));
      _title.clear();
    }

    Widget group<T>(String label, List<T> values, String Function(T) name, Set<T> selected, void Function(T) onTap) => Padding(
          padding: const EdgeInsets.only(bottom: 22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: context.text.titleMedium),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final v in values) FilterChip(label: Text(name(v)), selected: selected.contains(v), onSelected: (_) => onTap(v)),
            ]),
          ]),
        );

    return [
      Text('Preferred job titles', style: context.text.titleMedium),
      const SizedBox(height: 10),
      TextField(
        controller: _title,
        textCapitalization: TextCapitalization.words,
        onSubmitted: (_) => addTitle(),
        decoration: InputDecoration(
          hintText: 'e.g. Accountant',
          suffixIcon: IconButton(tooltip: 'Add job title', onPressed: addTitle, icon: const Icon(Icons.add_rounded)),
        ),
      ),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final t in p.titles)
          InputChip(label: Text(t), onDeleted: () => setState(() => _draft = _draft.copyWith(preferences: with_(titles: p.titles.where((x) => x != t).toList())))),
      ]),
      const SizedBox(height: 22),
      group('Industries', Industry.values, (e) => e.label, p.industries,
          (v) => setState(() => _draft = _draft.copyWith(preferences: with_(industries: flip(p.industries, v))))),
      group('Locations', sierraLeoneLocations, (e) => e, p.locations,
          (v) => setState(() => _draft = _draft.copyWith(preferences: with_(locations: flip(p.locations, v))))),
      group('Remote preference', WorkMode.values, (e) => e.label, p.workModes,
          (v) => setState(() => _draft = _draft.copyWith(preferences: with_(modes: flip(p.workModes, v))))),
      group('Employment type', EmploymentType.values, (e) => e.label, p.employmentTypes,
          (v) => setState(() => _draft = _draft.copyWith(preferences: with_(types: flip(p.employmentTypes, v))))),
      TextFormField(
        controller: _salary,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: 'Minimum monthly salary (SLE)', prefixText: 'SLE '),
        validator: (v) => (v ?? '').trim().isEmpty || int.tryParse(v!.replaceAll(',', '').trim()) != null ? null : 'Enter a number',
      ),
    ];
  }

  // ---- Dialogs -----------------------------------------------------------------

  Future<List<String>?> _simpleForm(String title, List<String> labels, {List<String>? initial}) => showDialog<List<String>>(
        context: context,
        builder: (_) => _SimpleFormDialog(title: title, labels: labels, initial: initial),
      );

  Future<void> _editExperience(int? index) async {
    final e = index == null ? null : _draft.experience[index];
    final r = await showDialog<Experience>(context: context, builder: (_) => _ExperienceDialog(initial: e));
    if (r == null) return;
    final list = [..._draft.experience];
    if (index == null) {
      list.insert(0, r);
    } else {
      list[index] = r;
    }
    setState(() => _draft = _draft.copyWith(experience: list));
  }

  Future<void> _editEducation(int? index) async {
    final e = index == null ? null : _draft.education[index];
    final r = await _simpleForm(
      index == null ? 'Add education' : 'Edit education',
      ['School or university', 'Degree / certificate', 'Field of study', 'Start year', 'End year (blank if ongoing)'],
      initial: e == null ? null : [e.school, e.degree, e.field, '${e.startYear}', e.endYear?.toString() ?? ''],
    );
    if (r == null) return;
    final edu = Education(school: r[0], degree: r[1], field: r[2], startYear: int.tryParse(r[3]) ?? DateTime.now().year, endYear: int.tryParse(r[4]));
    final list = [..._draft.education];
    if (index == null) {
      list.insert(0, edu);
    } else {
      list[index] = edu;
    }
    setState(() => _draft = _draft.copyWith(education: list));
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.title, required this.subtitle, this.onEdit, required this.onDelete});
  final String title;
  final String subtitle;
  final VoidCallback? onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Card(
          child: ListTile(
            onTap: onEdit,
            title: Text(title, style: context.text.titleSmall),
            subtitle: Text(subtitle),
            trailing: IconButton(tooltip: 'Remove $title', onPressed: onDelete, icon: const Icon(Icons.delete_outline_rounded)),
          ),
        ),
      );
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: OutlinedButton.icon(onPressed: onTap, icon: const Icon(Icons.add_rounded), label: Text(label)),
      );
}

class _SimpleFormDialog extends StatefulWidget {
  const _SimpleFormDialog({required this.title, required this.labels, this.initial});
  final String title;
  final List<String> labels;
  final List<String>? initial;

  @override
  State<_SimpleFormDialog> createState() => _SimpleFormDialogState();
}

class _SimpleFormDialogState extends State<_SimpleFormDialog> {
  late final _ctrls = [for (var i = 0; i < widget.labels.length; i++) TextEditingController(text: widget.initial?[i] ?? '')];
  final _key = GlobalKey<FormState>();

  @override
  void dispose() {
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: Form(
          key: _key,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (var i = 0; i < widget.labels.length; i++) ...[
                TextFormField(
                  controller: _ctrls[i],
                  decoration: InputDecoration(labelText: widget.labels[i]),
                  keyboardType: widget.labels[i].toLowerCase().contains('year') ? TextInputType.number : TextInputType.text,
                  validator: (v) => widget.labels[i].contains('blank') || (v ?? '').trim().isNotEmpty ? null : 'Required',
                ),
                const SizedBox(height: 12),
              ],
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
            onPressed: () {
              if (_key.currentState!.validate()) Navigator.pop(context, _ctrls.map((c) => c.text.trim()).toList());
            },
            child: const Text('Done'),
          ),
        ],
      );
}

class _ExperienceDialog extends StatefulWidget {
  const _ExperienceDialog({this.initial});
  final Experience? initial;

  @override
  State<_ExperienceDialog> createState() => _ExperienceDialogState();
}

class _ExperienceDialogState extends State<_ExperienceDialog> {
  final _key = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.initial?.title);
  late final _company = TextEditingController(text: widget.initial?.company);
  late final _desc = TextEditingController(text: widget.initial?.description);
  late String _location = widget.initial?.location ?? 'Freetown';
  late DateTime _start = widget.initial?.start ?? DateTime(DateTime.now().year - 1);
  late DateTime? _end = widget.initial?.end;

  @override
  void dispose() {
    _title.dispose();
    _company.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime initial) => showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(1970),
        lastDate: DateTime.now(),
        initialDatePickerMode: DatePickerMode.year,
      );

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.initial == null ? 'Add experience' : 'Edit experience'),
        content: Form(
          key: _key,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(controller: _title, decoration: const InputDecoration(labelText: 'Job title'), validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _company, decoration: const InputDecoration(labelText: 'Employer'), validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: sierraLeoneLocations.contains(_location) ? _location : null,
                decoration: const InputDecoration(labelText: 'Location'),
                items: [for (final l in sierraLeoneLocations) DropdownMenuItem(value: l, child: Text(l))],
                onChanged: (v) => _location = v ?? _location,
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final d = await _pick(_start);
                      if (d != null) setState(() => _start = d);
                    },
                    child: Text('From ${Fmt.monthYear(_start)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _end == null
                        ? null
                        : () async {
                            final d = await _pick(_end!);
                            if (d != null) setState(() => _end = d);
                          },
                    child: Text(_end == null ? 'Present' : 'To ${Fmt.monthYear(_end!)}'),
                  ),
                ),
              ]),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _end == null,
                title: const Text('I currently work here'),
                onChanged: (v) => setState(() => _end = v == true ? null : DateTime.now()),
              ),
              TextFormField(controller: _desc, minLines: 3, maxLines: 6, decoration: const InputDecoration(labelText: 'What did you do? (optional)')),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
            onPressed: () {
              if (!_key.currentState!.validate()) return;
              Navigator.pop(
                context,
                Experience(title: _title.text.trim(), company: _company.text.trim(), location: _location, start: _start, end: _end, description: _desc.text.trim()),
              );
            },
            child: const Text('Done'),
          ),
        ],
      );
}

class _LanguageDialog extends StatefulWidget {
  const _LanguageDialog();

  @override
  State<_LanguageDialog> createState() => _LanguageDialogState();
}

class _LanguageDialogState extends State<_LanguageDialog> {
  static const _common = ['English', 'Krio', 'Mende', 'Temne', 'Limba', 'Kono', 'French', 'Arabic'];
  static const _levels = ['Native', 'Fluent', 'Conversational', 'Basic'];
  String _name = 'Krio';
  String _level = 'Fluent';

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Add language'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _name,
            decoration: const InputDecoration(labelText: 'Language'),
            items: [for (final l in _common) DropdownMenuItem(value: l, child: Text(l))],
            onChanged: (v) => setState(() => _name = v ?? _name),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: _level,
            decoration: const InputDecoration(labelText: 'Level'),
            items: [for (final l in _levels) DropdownMenuItem(value: l, child: Text(l))],
            onChanged: (v) => setState(() => _level = v ?? _level),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(64, 44)),
            onPressed: () => Navigator.pop(context, LanguageSkill(name: _name, level: _level)),
            child: const Text('Add'),
          ),
        ],
      );
}
