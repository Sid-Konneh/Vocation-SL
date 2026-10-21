import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/models.dart';
import '../../../providers/message_providers.dart';
import '../../../services/offer_letter_pdf.dart';
import '../../../widgets/common.dart';

/// Fill in an offer letter, preview the PDF, then send it to the candidate in
/// Messages. Returns true when sent.
Future<bool> sendOfferLetter(BuildContext context, WidgetRef ref, JobApplication a, Company company) async {
  final details = await Navigator.of(context).push<OfferLetterDetails>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _OfferLetterForm(application: a, company: company),
  ));
  if (details == null || !context.mounted) return false;

  final Uint8List bytes;
  try {
    bytes = await OfferLetterPdf.build(details, company);
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
  if (!context.mounted) return false;
  final send = await Navigator.of(context).push<bool>(MaterialPageRoute(
    builder: (_) => _OfferPreview(bytes: bytes, fileName: OfferLetterPdf.fileName(details), candidate: details.candidateName),
  ));
  if (send != true || !context.mounted) return false;

  try {
    final messages = ref.read(messageBackendProvider);
    final file = await messages.uploadAttachment(OfferLetterPdf.fileName(details), bytes);
    await messages.send(
      a.id,
      'Dear ${details.candidateName.trim().split(RegExp(r'\s+')).first}, please find your offer letter for ${details.jobTitle.trim()} attached. '
      'Kindly reply by ${Fmt.date(details.replyBy)} to let us know your decision.',
      asEmployer: true,
      attachment: file,
    );
    ref.invalidate(messageThreadProvider(a.id));
    if (context.mounted) showSnack(context, 'Offer letter sent to ${details.candidateName}');
    return true;
  } catch (e) {
    if (context.mounted) showError(context, e);
    return false;
  }
}

class _OfferLetterForm extends StatefulWidget {
  const _OfferLetterForm({required this.application, required this.company});
  final JobApplication application;
  final Company company;

  @override
  State<_OfferLetterForm> createState() => _OfferLetterFormState();
}

class _OfferLetterFormState extends State<_OfferLetterForm> {
  late final _name = TextEditingController(text: widget.application.applicant.fullName);
  late final _title = TextEditingController(text: widget.application.job?.title ?? '');
  late final _contract = TextEditingController(text: widget.application.job?.employmentType.label ?? 'Full-time');
  late final _salary = TextEditingController(text: '${widget.application.job?.salaryMax ?? widget.application.job?.salaryMin ?? ''}');
  late final _place = TextEditingController(text: widget.application.job?.location ?? widget.company.location);
  final _reportingTo = TextEditingController();
  final _probation = TextEditingController(text: '3 months');
  final _other = TextEditingController();
  final _signName = TextEditingController();
  final _signTitle = TextEditingController();
  late String _period = const ['month', 'year', 'week', 'day', 'hour'].contains(widget.application.job?.salaryPeriod)
      ? widget.application.job!.salaryPeriod
      : 'month';
  DateTime _start = DateTime.now().add(const Duration(days: 14));
  DateTime _replyBy = DateTime.now().add(const Duration(days: 7));
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _title, _contract, _salary, _place, _reportingTo, _probation, _other, _signName, _signTitle]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: start ? _start : _replyBy,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: start ? 'Start date' : 'Reply by',
    );
    if (d != null) setState(() => start ? _start = d : _replyBy = d);
  }

  void _done() {
    final details = OfferLetterDetails(
      candidateName: _name.text,
      jobTitle: _title.text,
      contractType: _contract.text.trim().isEmpty ? 'Full-time' : _contract.text,
      salary: int.tryParse(_salary.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
      salaryPeriod: _period,
      startDate: _start,
      replyBy: _replyBy,
      placeOfWork: _place.text,
      signatoryName: _signName.text,
      signatoryTitle: _signTitle.text,
      reportingTo: _reportingTo.text,
      probation: _probation.text,
      otherTerms: _other.text,
    );
    final problem = details.validate();
    if (problem.isNotEmpty) {
      setState(() => _error = problem);
      return;
    }
    Navigator.pop(context, details);
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label, {String? hint, int lines = 1, TextInputType? type, int? max}) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(
            controller: c,
            minLines: lines,
            maxLines: lines == 1 ? 1 : lines + 3,
            maxLength: max,
            keyboardType: type,
            textCapitalization: type == null ? TextCapitalization.sentences : TextCapitalization.none,
            decoration: InputDecoration(labelText: label, hintText: hint, alignLabelWithHint: lines > 1),
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Offer letter')),
      body: ResponsiveCenter(
        maxWidth: AppSpacing.maxReadingWidth,
        child: ListView(padding: const EdgeInsets.all(AppSpacing.gutter), children: [
          Text('Fill in the offer. We\'ll make a PDF letter on ${widget.company.name}\'s behalf for you to check before it\'s sent.',
              style: context.text.bodyMedium),
          const SizedBox(height: 16),
          field(_name, 'Candidate\'s full name'),
          field(_title, 'Job title'),
          field(_contract, 'Contract', hint: 'Full-time, 12-month fixed term...'),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: field(_salary, 'Salary (SLE, gross)', type: TextInputType.number)),
            const SizedBox(width: 12),
            SizedBox(
              width: 140,
              child: DropdownButtonFormField<String>(
                initialValue: _period,
                decoration: const InputDecoration(labelText: 'Per'),
                items: [for (final p in const ['month', 'year', 'week', 'day', 'hour']) DropdownMenuItem(value: p, child: Text(p))],
                onChanged: (v) => setState(() => _period = v ?? _period),
              ),
            ),
          ]),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pick(true),
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text('Starts ${Fmt.date(_start)}', overflow: TextOverflow.ellipsis),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pick(false),
                icon: const Icon(Icons.reply_rounded, size: 18),
                label: Text('Reply by ${Fmt.date(_replyBy)}', overflow: TextOverflow.ellipsis),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          field(_place, 'Place of work'),
          field(_reportingTo, 'Reporting to (optional)', hint: 'e.g. Finance Manager'),
          field(_probation, 'Probation (optional)'),
          field(_other, 'Other terms (optional)', hint: 'Working hours, allowances, leave...', lines: 3, max: 1500),
          Text('Signed by', style: context.text.titleSmall),
          const SizedBox(height: 8),
          field(_signName, 'Name'),
          field(_signTitle, 'Job title', hint: 'e.g. Managing Director'),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: context.palette.surface, borderRadius: BorderRadius.circular(AppSpacing.radius)),
            child: Text(
              'This is a standard template. Check that the terms match your organisation\'s policies and Sierra Leone '
              'employment law before you send it.',
              style: context.text.bodySmall?.copyWith(color: context.palette.muted),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: context.text.bodyMedium?.copyWith(color: AppColors.danger)),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(onPressed: _done, icon: const Icon(Icons.picture_as_pdf_outlined), label: const Text('Make the letter')),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }
}

class _OfferPreview extends StatelessWidget {
  const _OfferPreview({required this.bytes, required this.fileName, required this.candidate});
  final Uint8List bytes;
  final String fileName;
  final String candidate;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Check the letter')),
        body: PdfViewer.data(bytes, sourceName: fileName),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel'))),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton.icon(
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.send_rounded, size: 18),
                  label: Text('Send to ${candidate.split(' ').first}', overflow: TextOverflow.ellipsis),
                ),
              ),
            ]),
          ),
        ),
      );
}
