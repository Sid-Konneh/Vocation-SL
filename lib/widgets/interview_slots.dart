import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/formatters.dart';
import '../models/models.dart';
import '../providers/hiring_providers.dart';
import 'common.dart';

/// Employer: offer up to 3 interview times. Returns true when sent.
Future<bool> offerInterviewTimes(BuildContext context, WidgetRef ref, JobApplication a, {String defaultPlace = ''}) async {
  final result = await showDialog<({List<DateTime> slots, String place, String note})>(
    context: context,
    builder: (_) => _OfferTimesDialog(name: a.applicant.fullName.split(' ').first, defaultPlace: defaultPlace),
  );
  if (result == null || !context.mounted) return false;
  try {
    await ref.read(hiringBackendProvider).proposeInterview(a.id, result.slots, place: result.place, note: result.note);
    ref.invalidate(interviewProposalProvider(a.id));
    if (context.mounted) showSnack(context, 'Times sent. ${a.applicant.fullName.split(' ').first} will pick one in the app.');
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}

class _OfferTimesDialog extends StatefulWidget {
  const _OfferTimesDialog({required this.name, required this.defaultPlace});
  final String name;
  final String defaultPlace;

  @override
  State<_OfferTimesDialog> createState() => _OfferTimesDialogState();
}

class _OfferTimesDialogState extends State<_OfferTimesDialog> {
  final _slots = <DateTime>[];
  late final _place = TextEditingController(text: widget.defaultPlace);
  final _note = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _place.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final now = DateTime.now();
    final last = _slots.isEmpty ? null : _slots.last;
    final date = await showDatePicker(
      context: context,
      initialDate: last ?? now.add(const Duration(days: 2)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 120)),
      helpText: 'Interview date',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: last == null ? const TimeOfDay(hour: 10, minute: 0) : TimeOfDay.fromDateTime(last),
      helpText: 'Interview time',
    );
    if (time == null) return;
    final at = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (at.isBefore(DateTime.now().add(const Duration(hours: 1)))) {
        _error = 'Choose a time at least an hour from now.';
      } else if (_slots.contains(at)) {
        _error = 'You already added that time.';
      } else {
        _error = null;
        _slots
          ..add(at)
          ..sort();
      }
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Offer interview times'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Add up to 3 times. ${widget.name} picks one in the app, and you both get a reminder the day before.',
                  style: context.text.bodyMedium),
              const SizedBox(height: 12),
              for (final s in _slots)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.event_rounded, color: context.colors.primary),
                    title: Text(Fmt.dateTime(s)),
                    trailing: IconButton(
                      tooltip: 'Remove this time',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _slots.remove(s)),
                    ),
                  ),
                ),
              if (_slots.length < 3)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _add,
                    icon: const Icon(Icons.add_rounded),
                    label: Text(_slots.isEmpty ? 'Add a time' : 'Add another time'),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(_error!, style: context.text.bodySmall?.copyWith(color: AppColors.danger)),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _place,
                maxLength: 300,
                decoration: const InputDecoration(labelText: 'Where', hintText: 'Office address, or "Phone call", or a video link'),
              ),
              TextField(
                controller: _note,
                maxLength: 1000,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Note (optional)', hintText: 'What to bring, who to ask for', alignLabelWithHint: true),
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: _slots.isEmpty ? null : () => Navigator.pop(context, (slots: List.of(_slots), place: _place.text, note: _note.text)),
            child: const Text('Send times'),
          ),
        ],
      );
}

/// Employer: what happened to the times offered.
class InterviewOfferStatus extends ConsumerWidget {
  const InterviewOfferStatus({super.key, required this.applicationId, required this.candidateName});
  final String applicationId;
  final String candidateName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(interviewProposalProvider(applicationId)).value;
    if (p == null || p.status == InterviewProposalStatus.cancelled) return const SizedBox.shrink();
    final muted = context.palette.muted;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(AppSpacing.radius)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (p.isChosen) ...[
          Text('$candidateName chose ${Fmt.dateTime(p.chosenAt!)}', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          Text('${Fmt.countdown(p.chosenAt!)}. You\'ll both get a reminder the day before.', style: context.text.bodySmall?.copyWith(color: muted)),
        ] else ...[
          Text('Waiting for $candidateName to choose a time', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          for (final s in p.slots)
            Text('• ${Fmt.dateTime(s)}${s.isBefore(DateTime.now()) ? ' (passed)' : ''}', style: context.text.bodySmall?.copyWith(color: muted)),
          if (p.upcomingSlots().isEmpty)
            Text('All the times have passed. Offer new times.', style: context.text.bodySmall?.copyWith(color: AppColors.warning)),
        ],
        if (p.place.isNotEmpty) Text('Where: ${p.place}', style: context.text.bodySmall?.copyWith(color: muted)),
      ]),
    );
  }
}

/// Job seeker: pick one of the times the employer offered.
class ChooseInterviewCard extends ConsumerStatefulWidget {
  const ChooseInterviewCard({super.key, required this.application, required this.onChosen});
  final JobApplication application;
  final VoidCallback onChosen;

  @override
  ConsumerState<ChooseInterviewCard> createState() => _ChooseInterviewCardState();
}

class _ChooseInterviewCardState extends ConsumerState<ChooseInterviewCard> {
  DateTime? _picked;
  bool _saving = false;

  Future<void> _confirm(InterviewProposal p) async {
    final slot = _picked;
    if (slot == null) return;
    setState(() => _saving = true);
    try {
      await ref.read(hiringBackendProvider).chooseSlot(p.id, slot);
      ref.invalidate(interviewProposalProvider(widget.application.id));
      widget.onChosen();
      if (mounted) showSnack(context, 'Interview confirmed for ${Fmt.dateTime(slot)}');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = ref.watch(interviewProposalProvider(widget.application.id)).value;
    if (p == null || p.status == InterviewProposalStatus.cancelled || !widget.application.status.isActive) return const SizedBox.shrink();
    const orange = Color(0xFFD9570F);
    final muted = context.palette.muted;

    Widget frame(List<Widget> children) => Container(
          margin: const EdgeInsets.only(top: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppSpacing.radius)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        );

    if (p.isChosen) {
      return frame([
        Row(children: [
          const Icon(Icons.event_available_rounded, color: orange),
          const SizedBox(width: 10),
          Expanded(child: Text('Interview ${Fmt.countdown(p.chosenAt!)}', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
        ]),
        const SizedBox(height: 4),
        Text(Fmt.dateTime(p.chosenAt!), style: context.text.bodyLarge),
        if (p.place.isNotEmpty) Text('Where: ${p.place}', style: context.text.bodyMedium),
        if (p.note.isNotEmpty) Text(p.note, style: context.text.bodyMedium?.copyWith(color: muted)),
        const SizedBox(height: 4),
        Text('We\'ll remind you the day before. Can\'t make it? Tell the employer in Messages.', style: context.text.bodySmall?.copyWith(color: muted)),
      ]);
    }

    final upcoming = p.upcomingSlots();
    return frame([
      Row(children: [
        const Icon(Icons.event_rounded, color: orange),
        const SizedBox(width: 10),
        Expanded(child: Text('Choose your interview time', style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
      ]),
      if (p.place.isNotEmpty) ...[const SizedBox(height: 4), Text('Where: ${p.place}', style: context.text.bodyMedium)],
      if (p.note.isNotEmpty) Text(p.note, style: context.text.bodyMedium?.copyWith(color: muted)),
      const SizedBox(height: 8),
      if (upcoming.isEmpty)
        Text('These times have passed. Ask the employer for new times in Messages.', style: context.text.bodyMedium)
      else ...[
        RadioGroup<DateTime>(
          groupValue: _picked,
          onChanged: (v) => setState(() => _picked = v),
          child: Column(children: [
            for (final s in upcoming) RadioListTile<DateTime>(contentPadding: EdgeInsets.zero, value: s, title: Text(Fmt.dateTime(s))),
          ]),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _picked == null || _saving ? null : () => _confirm(p),
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check_rounded, size: 18),
            label: const Text('Confirm this time'),
          ),
        ),
        const SizedBox(height: 4),
        Text('None of these work? Tell the employer in Messages.', style: context.text.bodySmall?.copyWith(color: muted)),
      ],
    ]);
  }
}
