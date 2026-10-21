import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/errors.dart';
import '../models/models.dart';

/// What the employer fills in for an offer letter.
class OfferLetterDetails {
  const OfferLetterDetails({
    required this.candidateName,
    required this.jobTitle,
    required this.contractType,
    required this.salary,
    required this.salaryPeriod,
    required this.startDate,
    required this.replyBy,
    required this.placeOfWork,
    required this.signatoryName,
    required this.signatoryTitle,
    this.reportingTo = '',
    this.probation = '',
    this.otherTerms = '',
  });

  final String candidateName;
  final String jobTitle;
  final String contractType;
  final int salary;

  /// 'month', 'year', 'week', 'day' or 'hour'.
  final String salaryPeriod;
  final DateTime startDate;
  final DateTime replyBy;
  final String placeOfWork;
  final String signatoryName;
  final String signatoryTitle;
  final String reportingTo;
  final String probation;
  final String otherTerms;

  String validate() {
    if (candidateName.trim().isEmpty) return 'Enter the candidate\'s name.';
    if (jobTitle.trim().isEmpty) return 'Enter the job title.';
    if (salary <= 0) return 'Enter the salary.';
    if (signatoryName.trim().isEmpty || signatoryTitle.trim().isEmpty) return 'Enter who is signing the letter and their job title.';
    if (replyBy.isBefore(DateTime.now().subtract(const Duration(days: 1)))) return 'The reply date has passed.';
    return '';
  }
}

/// Builds a one-page offer letter PDF on the company's behalf.
class OfferLetterPdf {
  static const _green = PdfColor.fromInt(0xFF3F7A1F);
  static const _ink = PdfColor.fromInt(0xFF14171A);
  static const _muted = PdfColor.fromInt(0xFF5E6670);
  static const _line = PdfColor.fromInt(0xFFE3E7E0);

  static String fileName(OfferLetterDetails d) => 'Offer letter - ${d.candidateName.trim()}.pdf';

  static Future<Uint8List> build(OfferLetterDetails d, Company company, {DateTime? today}) async {
    final problem = d.validate();
    if (problem.isNotEmpty) throw ValidationException(problem);

    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/PlusJakartaSans-400.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/PlusJakartaSans-700.ttf'));
    final date = DateFormat('d MMMM yyyy');
    final money = NumberFormat.decimalPattern('en_GB');
    final firstName = d.candidateName.trim().split(RegExp(r'\s+')).first;

    final contact = [
      if (company.address.trim().isNotEmpty) company.address.trim(),
      if (company.location.trim().isNotEmpty && !company.address.contains(company.location)) company.location.trim(),
      if (company.phone.trim().isNotEmpty) company.phone.trim(),
      if (company.email.trim().isNotEmpty) company.email.trim(),
    ].join('  ·  ');

    pw.TableRow term(String label, String value) => pw.TableRow(children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 5),
            child: pw.Text(label, style: pw.TextStyle(fontSize: 10, color: _muted, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Padding(padding: const pw.EdgeInsets.symmetric(vertical: 5), child: pw.Text(value, style: const pw.TextStyle(fontSize: 10.5, color: _ink))),
        ]);

    pw.Widget para(String t) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 9),
          child: pw.Text(t, style: const pw.TextStyle(fontSize: 10.5, color: _ink, lineSpacing: 2.5)),
        );

    pw.Widget blank(String label) => pw.Expanded(
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.SizedBox(height: 22),
            pw.Container(height: 0.8, color: _muted),
            pw.SizedBox(height: 3),
            pw.Text(label, style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
          ]),
        );

    final doc = pw.Document(title: 'Offer letter – ${d.candidateName}', author: company.name, creator: 'Vocation SL');
    doc.addPage(pw.MultiPage(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(48, 40, 48, 36),
      footer: (c) => pw.Row(children: [
        pw.Expanded(child: pw.Text('Sent through Vocation SL', style: const pw.TextStyle(fontSize: 8, color: _muted))),
        pw.Text('Page ${c.pageNumber} of ${c.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: _muted)),
      ]),
      build: (c) => [
        pw.Text(company.name, style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _green)),
        if (contact.isNotEmpty) pw.Text(contact, style: const pw.TextStyle(fontSize: 9, color: _muted)),
        pw.SizedBox(height: 8),
        pw.Container(height: 1.2, color: _green),
        pw.SizedBox(height: 18),
        pw.Text(date.format(today ?? DateTime.now()), style: const pw.TextStyle(fontSize: 10.5, color: _ink)),
        pw.SizedBox(height: 12),
        para('Dear ${d.candidateName.trim()},'),
        pw.Text('Offer of employment: ${d.jobTitle.trim()}', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _ink)),
        pw.SizedBox(height: 10),
        para('Following your application and interview, we are pleased to offer you the position of ${d.jobTitle.trim()} '
            'at ${company.name}, on the terms set out below.'),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Table(columnWidths: const {0: pw.FixedColumnWidth(120), 1: pw.FlexColumnWidth()}, children: [
            term('Position', d.jobTitle.trim()),
            term('Contract', d.contractType.trim()),
            term('Start date', date.format(d.startDate)),
            if (d.placeOfWork.trim().isNotEmpty) term('Place of work', d.placeOfWork.trim()),
            if (d.reportingTo.trim().isNotEmpty) term('Reporting to', d.reportingTo.trim()),
            term('Salary', 'SLE ${money.format(d.salary)} per ${d.salaryPeriod} (gross)'),
            if (d.probation.trim().isNotEmpty) term('Probation', d.probation.trim()),
          ]),
        ),
        pw.SizedBox(height: 12),
        if (d.otherTerms.trim().isNotEmpty) ...[
          pw.Text('Other terms', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: _ink)),
          pw.SizedBox(height: 4),
          para(d.otherTerms.trim()),
        ],
        para('This offer is subject to satisfactory references and any documents we have asked you for. '
            'Your full terms of employment will be set out in your contract.'),
        para('Please let us know whether you accept this offer by ${date.format(d.replyBy)}. You can reply in the '
            'Vocation SL app, or sign the acceptance below and send a copy back to us.'),
        para('We look forward to welcoming you to the team, $firstName.'),
        pw.SizedBox(height: 6),
        para('Yours sincerely,'),
        pw.SizedBox(height: 26),
        pw.Container(width: 180, height: 0.8, color: _muted),
        pw.SizedBox(height: 3),
        pw.Text(d.signatoryName.trim(), style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: _ink)),
        pw.Text('${d.signatoryTitle.trim()}, ${company.name}', style: const pw.TextStyle(fontSize: 10, color: _muted)),
        pw.SizedBox(height: 22),
        pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFF6F8F4), borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text('Acceptance', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: _ink)),
            pw.SizedBox(height: 4),
            pw.Text('I, ${d.candidateName.trim()}, accept the offer of the position of ${d.jobTitle.trim()} on the terms above.',
                style: const pw.TextStyle(fontSize: 10, color: _ink)),
            pw.Row(children: [blank('Signature'), pw.SizedBox(width: 24), blank('Date')]),
          ]),
        ),
      ],
    ));
    return doc.save();
  }
}
