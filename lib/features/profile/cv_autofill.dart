import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/models.dart';
import '../../providers/core_providers.dart';
import '../../services/cv_text.dart';
import '../../widgets/common.dart';

/// Reads a CV on the device, shows what was found and lets the user pick
/// what to add. Pass the file's [bytes] when they are at hand (just
/// uploaded); otherwise the CV at [resume]'s storage path is downloaded.
/// Returns the updated profile, or null if they cancel.
Future<AppUser?> fillProfileFromCv(
  BuildContext context,
  WidgetRef ref,
  AppUser user, {
  Uint8List? bytes,
  DocumentFormat? format,
  Resume? resume,
}) async {
  final path = resume?.storagePath;
  if (bytes == null && (path == null || path.isEmpty)) {
    showSnack(context, 'Upload your CV first.', error: true);
    return null;
  }
  Future<CvExtract> read() async {
    final data = bytes ?? await ref.read(backendProvider).downloadDocument(path!);
    return readCvOnDevice(data, format ?? resume?.format ?? DocumentFormat.fromFileName(resume?.fileName ?? ''));
  }

  final reading = read();
  final found = await showDialog<CvExtract>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ReadingDialog(future: reading),
  );
  if (found == null || !context.mounted) return null;
  if (found.isEmpty) {
    showSnack(context, 'We couldn\'t find profile details in that CV. You can fill your profile in by hand.');
    return null;
  }
  return showModalBottomSheet<AppUser>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ReviewSheet(user: user, found: found),
  );
}

class _ReadingDialog extends StatefulWidget {
  const _ReadingDialog({required this.future});
  final Future<CvExtract> future;

  @override
  State<_ReadingDialog> createState() => _ReadingDialogState();
}

class _ReadingDialogState extends State<_ReadingDialog> {
  Object? _error;

  @override
  void initState() {
    super.initState();
    widget.future.then((v) {
      if (mounted) Navigator.of(context).pop(v);
    }, onError: (Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        content: _error != null
            ? Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.error_outline_rounded, color: AppColors.danger),
                const SizedBox(height: 12),
                Text(AppException.describe(_error!), style: context.text.bodyMedium),
              ])
            : const Row(children: [
                SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
                SizedBox(width: 18),
                Expanded(child: Text('Reading your CV…\nThis takes a few seconds.')),
              ]),
        actions: [if (_error != null) TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
      );
}
class _ReviewSheet extends StatefulWidget {
  const _ReviewSheet({required this.user, required this.found});
  final AppUser user;
  final CvExtract found;

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  late final Set<CvSection> _chosen = {for (final s in CvSection.values) if (_lines(s).isNotEmpty) s};

  List<String> _lines(CvSection s) {
    final f = widget.found;
    final u = widget.user;
    String? only(String current, String found, String label) => current.trim().isEmpty && found.isNotEmpty ? '$label: $found' : null;
    return switch (s) {
      CvSection.basics => [
          only(u.headline, f.headline, 'Headline'),
          only(u.phone, f.phone, 'Phone'),
          only(u.location, f.location, 'Location'),
          if (u.about.trim().isEmpty && f.about.isNotEmpty) 'About: ${f.about.length > 120 ? '${f.about.substring(0, 120)}…' : f.about}',
          only(u.linkedinUrl, f.linkedinUrl, 'LinkedIn'),
          only(u.portfolioUrl, f.portfolioUrl, 'Portfolio'),
        ].whereType<String>().toList(),
      CvSection.experience => [
          for (final e in f.experience)
            '${e.title}${e.company.isEmpty ? '' : ' · ${e.company}'} (${Fmt.dateShort(e.start)} – ${e.end == null ? 'present' : Fmt.dateShort(e.end!)})',
        ],
      CvSection.education => [for (final e in f.education) '${[e.degree, e.field].where((s) => s.isNotEmpty).join(', ')} · ${e.school}'],
      CvSection.skills => f.skills.isEmpty ? [] : [f.skills.join(', ')],
      CvSection.languages => [for (final l in f.languages) '${l.name} (${l.level})'],
      CvSection.certifications => [for (final c in f.certifications) '${c.name}${c.issuer.isEmpty ? '' : ' · ${c.issuer}'} · ${c.year}'],
    };
  }

  @override
  Widget build(BuildContext context) {
    final sections = [for (final s in CvSection.values) if (_lines(s).isNotEmpty) s];
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, scroll) => Column(children: [
        Expanded(
          child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 8, 20, 12), children: [
            Text('We found this in your CV', style: context.text.titleLarge),
            const SizedBox(height: 6),
            Text('Choose what to add. Nothing you already filled in is replaced. You can edit everything afterwards.',
                style: context.text.bodyMedium?.copyWith(color: context.palette.muted)),
            const SizedBox(height: 12),
            for (final s in sections)
              Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: CheckboxListTile(
                  value: _chosen.contains(s),
                  onChanged: (v) => setState(() => v == true ? _chosen.add(s) : _chosen.remove(s)),
                  title: Text(s.label, style: context.text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(_lines(s).join('\n'), style: context.text.bodySmall),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
              ),
            Text('Please check the details: reading a CV automatically can make mistakes.',
                style: context.text.bodySmall?.copyWith(color: context.palette.muted)),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Not now'))),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _chosen.isEmpty ? null : () => Navigator.pop(context, widget.found.applyTo(widget.user, _chosen)),
                  child: const Text('Add to my profile'),
                ),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}
