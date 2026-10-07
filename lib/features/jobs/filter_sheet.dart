import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/job_providers.dart';

/// Opens the full filter sheet and resolves with the new filter (or null).
Future<JobFilter?> showFilterSheet(BuildContext context, JobFilter current) => showModalBottomSheet<JobFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 720),
      builder: (_) => _FilterSheet(initial: current),
    );

class _FilterSheet extends ConsumerStatefulWidget {
  const _FilterSheet({required this.initial});
  final JobFilter initial;

  @override
  ConsumerState<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends ConsumerState<_FilterSheet> {
  late JobFilter f = widget.initial;

  Set<T> _toggle<T>(Set<T> s, T v) => s.contains(v) ? ({...s}..remove(v)) : {...s, v};

  @override
  Widget build(BuildContext context) {
    final companies = ref.watch(companiesProvider).value?.data ?? const <Company>[];
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
          child: Row(children: [
            Expanded(child: Text('Filters', style: context.text.titleLarge)),
            IconButton(tooltip: 'Close', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded)),
          ]),
        ),
        const Divider(),
        Expanded(
          child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 16, 20, 24), children: [
            _Section(
              'Sort by',
              child: _Chips(
                values: JobSort.values,
                label: (s) => s.label,
                selected: (s) => f.sort == s,
                onTap: (s) => setState(() => f = f.copyWith(sort: s)),
              ),
            ),
            _Section(
              'Location',
              child: _Chips(
                values: sierraLeoneLocations,
                label: (s) => s,
                selected: f.locations.contains,
                onTap: (s) => setState(() => f = f.copyWith(locations: _toggle(f.locations, s))),
              ),
            ),
            _Section(
              'Remote status',
              child: _Chips(
                values: WorkMode.values,
                label: (s) => s.label,
                selected: f.workModes.contains,
                onTap: (s) => setState(() => f = f.copyWith(workModes: _toggle(f.workModes, s))),
              ),
            ),
            _Section(
              'Employment type',
              child: _Chips(
                values: EmploymentType.values,
                label: (s) => s.label,
                selected: f.employmentTypes.contains,
                onTap: (s) => setState(() => f = f.copyWith(employmentTypes: _toggle(f.employmentTypes, s))),
              ),
            ),
            _Section(
              'Industry',
              child: _Chips(
                values: Industry.values,
                label: (s) => s.label,
                selected: f.industries.contains,
                onTap: (s) => setState(() => f = f.copyWith(industries: _toggle(f.industries, s))),
              ),
            ),
            _Section(
              'Experience level',
              child: _Chips(
                values: ExperienceLevel.values,
                label: (s) => s.label,
                selected: f.experienceLevels.contains,
                onTap: (s) => setState(() => f = f.copyWith(experienceLevels: _toggle(f.experienceLevels, s))),
              ),
            ),
            _Section(
              'Minimum monthly salary',
              trailing: Text(f.minSalary == null ? 'Any' : 'SLE ${Fmt.money(f.minSalary!)}+',
                  style: context.text.titleSmall?.copyWith(color: context.colors.primary)),
              child: Slider(
                value: (f.minSalary ?? 0).toDouble(),
                min: 0,
                max: 25000,
                divisions: 25,
                label: f.minSalary == null ? 'Any' : 'SLE ${Fmt.money(f.minSalary!)}',
                semanticFormatterCallback: (v) => v == 0 ? 'Any salary' : 'At least SLE ${Fmt.money(v.round())} a month',
                onChanged: (v) => setState(() => f = f.copyWith(minSalary: () => v == 0 ? null : v.round())),
              ),
            ),
            _Section(
              'Date posted',
              child: _Chips(
                values: DatePosted.values,
                label: (s) => s.label,
                selected: (s) => f.datePosted == s,
                onTap: (s) => setState(() => f = f.copyWith(datePosted: s)),
              ),
            ),
            if (companies.isNotEmpty)
              _Section(
                'Company',
                child: DropdownButtonFormField<String?>(
                  initialValue: f.companyId,
                  isExpanded: true,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.business_rounded)),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Any company')),
                    for (final c in [...companies]..sort((a, b) => a.name.compareTo(b.name)))
                      DropdownMenuItem(value: c.id, child: Text(c.name, overflow: TextOverflow.ellipsis)),
                  ],
                  onChanged: (v) => setState(() => f = f.copyWith(companyId: () => v)),
                ),
              ),
          ]),
        ),
        DecoratedBox(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: context.palette.border))),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: Row(children: [
                TextButton(
                  onPressed: f.activeCount == 0 && f.sort == JobSort.relevance ? null : () => setState(() => f = JobFilter(query: f.query)),
                  style: TextButton.styleFrom(foregroundColor: context.colors.onSurface),
                  child: const Text('Clear all', style: TextStyle(decoration: TextDecoration.underline)),
                ),
                const Spacer(),
                FilledButton(
                  onPressed: () => Navigator.pop(context, f),
                  style: FilledButton.styleFrom(minimumSize: const Size(160, 52)),
                  child: Text(f.activeCount == 0 ? 'Show jobs' : 'Show jobs (${f.activeCount} filters)'),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, {required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Semantics(header: true, child: Text(title, style: context.text.titleMedium))),
            ?trailing,
          ]),
          const SizedBox(height: 12),
          child,
        ]),
      );
}

class _Chips<T> extends StatelessWidget {
  const _Chips({required this.values, required this.label, required this.selected, required this.onTap});
  final List<T> values;
  final String Function(T) label;
  final bool Function(T) selected;
  final void Function(T) onTap;

  @override
  Widget build(BuildContext context) => Wrap(spacing: 8, runSpacing: 8, children: [
        for (final v in values)
          FilterChip(
            label: Text(label(v)),
            selected: selected(v),
            onSelected: (_) => onTap(v),
            side: BorderSide(color: selected(v) ? context.colors.onSurface : context.palette.border, width: selected(v) ? 1.5 : 1),
            selectedColor: context.palette.surface,
            labelStyle: context.text.labelLarge?.copyWith(fontWeight: selected(v) ? FontWeight.w700 : FontWeight.w500),
          ),
      ]);
}
