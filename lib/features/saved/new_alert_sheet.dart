import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/models.dart';
import '../../providers/user_data_providers.dart';
import '../../widgets/common.dart';

/// "Notify me of new Accounting jobs in Bo": a job alert from a category,
/// a place and optional keywords.
Future<void> showNewAlertSheet(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _NewAlertSheet(),
    );

class _NewAlertSheet extends ConsumerStatefulWidget {
  const _NewAlertSheet();

  @override
  ConsumerState<_NewAlertSheet> createState() => _NewAlertSheetState();
}

class _NewAlertSheetState extends ConsumerState<_NewAlertSheet> {
  Industry? _industry;
  String? _location;
  final _keywords = TextEditingController();
  AlertFrequency _frequency = AlertFrequency.instant;
  bool _saving = false;

  @override
  void dispose() {
    _keywords.dispose();
    super.dispose();
  }

  String get _name {
    final what = [
      if (_keywords.text.trim().isNotEmpty) _keywords.text.trim(),
      if (_industry != null) _industry!.label,
    ].join(' · ');
    final where = _location == null ? '' : ' in $_location';
    return '${what.isEmpty ? 'All jobs' : what}$where';
  }

  Future<void> _save() async {
    if (_industry == null && _location == null && _keywords.text.trim().isEmpty) {
      showSnack(context, 'Choose a category, a place or a keyword.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final filter = JobFilter(
        query: _keywords.text.trim(),
        industries: {?_industry},
        locations: {?_location},
        sort: JobSort.newest,
      );
      await ref.read(alertsProvider.notifier).create(_name, filter, _frequency);
      if (!mounted) return;
      Navigator.pop(context);
      showSnack(context, 'Job alert saved. We\'ll notify you about new matching jobs.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('New job alert', style: context.text.titleLarge),
            const SizedBox(height: 4),
            Text('Get a notification when a matching job is posted.', style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
            const SizedBox(height: 16),
            DropdownButtonFormField<Industry?>(
              initialValue: _industry,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Category'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Any category')),
                for (final i in Industry.values) DropdownMenuItem(value: i, child: Text(i.label)),
              ],
              onChanged: (v) => setState(() => _industry = v),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _location,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'District or town'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Anywhere in Sierra Leone')),
                for (final l in sierraLeoneLocations) DropdownMenuItem(value: l, child: Text(l)),
              ],
              onChanged: (v) => setState(() => _location = v),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _keywords,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(labelText: 'Keywords (optional)', hintText: 'e.g. accountant, driver, nurse'),
            ),
            const SizedBox(height: 16),
            Text('How often', style: context.text.titleSmall),
            const SizedBox(height: 6),
            SegmentedButton<AlertFrequency>(
              segments: [for (final f in AlertFrequency.values) ButtonSegment(value: f, label: Text(f.label))],
              selected: {_frequency},
              onSelectionChanged: (s) => setState(() => _frequency = s.first),
            ),
            const SizedBox(height: 8),
            Text(
              _frequency == AlertFrequency.instant
                  ? 'One notification for each new job, as soon as it goes live.'
                  : 'One notification ${_frequency == AlertFrequency.daily ? 'each morning' : 'a week'} listing the new jobs.',
              style: context.text.bodySmall?.copyWith(color: context.palette.muted),
            ),
            const SizedBox(height: 20),
            Text('Alert name: $_name', style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.notifications_active_outlined),
              label: const Text('Save alert'),
            ),
          ]),
        ),
      );
}
