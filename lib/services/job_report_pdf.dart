import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/models.dart';

/// Typical reply time as words, e.g. "about 2 days".
String replyTimeText(double? hours) {
  if (hours == null) return '—';
  if (hours < 1) return 'under an hour';
  if (hours < 24) return 'about ${hours.round()} hours';
  final d = (hours / 24).round();
  return 'about $d day${d == 1 ? '' : 's'}';
}

/// The hiring report as a printable PDF (e.g. for donor reporting).
class JobReportPdf {
  static const _green = PdfColor.fromInt(0xFF3F7A1F);
  static const _ink = PdfColor.fromInt(0xFF14171A);
  static const _muted = PdfColor.fromInt(0xFF5E6670);
  static const _line = PdfColor.fromInt(0xFFE3E7E0);
  static const _bar = PdfColor.fromInt(0xFF3F7A1F);

  static String fileName(JobReport r) => 'Hiring report - ${r.title}.pdf';

  static Future<Uint8List> build(JobReport r, String companyName) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/PlusJakartaSans-400.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/PlusJakartaSans-700.ttf'));
    final date = DateFormat('d MMM yyyy');

    pw.Widget heading(String t) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 16, bottom: 6),
          child: pw.Text(t.toUpperCase(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _green, letterSpacing: 1.1)),
        );

    pw.Widget stat(String label, String value) => pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.only(right: 8),
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: _line), borderRadius: pw.BorderRadius.circular(6)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(label, style: const pw.TextStyle(fontSize: 8.5, color: _muted)),
              pw.SizedBox(height: 4),
              pw.Text(value, style: pw.TextStyle(fontSize: 15, fontWeight: pw.FontWeight.bold, color: _ink)),
            ]),
          ),
        );

    pw.Widget bars(List<(String, int)> rows) {
      final max = rows.fold<int>(0, (m, e) => e.$2 > m ? e.$2 : m);
      return pw.Column(children: [
        for (final (label, n) in rows)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 5),
            child: pw.Row(children: [
              pw.SizedBox(width: 150, child: pw.Text(label, style: const pw.TextStyle(fontSize: 9.5, color: _ink))),
              pw.Expanded(
                child: pw.LayoutBuilder(
                  builder: (c, box) => pw.Align(
                    alignment: pw.Alignment.centerLeft,
                    child: pw.Container(height: 9, width: max == 0 ? 0 : (box!.maxWidth * n / max), color: _bar),
                  ),
                ),
              ),
              pw.SizedBox(width: 36, child: pw.Text('$n', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold))),
            ]),
          ),
      ]);
    }

    final sources = r.sources.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final doc = pw.Document(title: 'Hiring report – ${r.title}', author: companyName, creator: 'Vocation SL');
    doc.addPage(pw.MultiPage(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
      footer: (c) => pw.Text('Vocation SL hiring report · generated ${date.format(r.generatedAt)} · page ${c.pageNumber} of ${c.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: _muted)),
      build: (c) => [
        pw.Text(companyName, style: const pw.TextStyle(fontSize: 10, color: _muted)),
        pw.Text('Hiring report: ${r.title}', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _ink)),
        pw.Text(
          [
            if (r.location.isNotEmpty) r.location,
            if (r.postedAt != null) 'posted ${date.format(r.postedAt!)}',
            if (r.deadline != null) 'deadline ${date.format(r.deadline!)}',
          ].join(' · '),
          style: const pw.TextStyle(fontSize: 9.5, color: _muted),
        ),
        pw.SizedBox(height: 14),
        pw.Row(children: [
          stat('Views', '${r.views}'),
          r.appliesExternally ? stat('Taps on "Apply on website"', '${r.applyClicks}') : stat('Applications', '${r.applications}'),
          stat('Typical reply time', replyTimeText(r.medianReplyHours)),
          stat('Hired', '${r.hired}'),
        ]),
        if (!r.appliesExternally) ...[
          heading('Pipeline'),
          bars([
            ('Applied', r.applications),
            ('Shortlisted', r.reached['shortlisted'] ?? 0),
            ('Interviewed', r.reached['interview'] ?? 0),
            ('Offered', r.reached['offer'] ?? 0),
            ('Hired', r.hired),
          ]),
          if (r.withdrawn > 0) pw.Text('${r.withdrawn} withdrew their application.', style: const pw.TextStyle(fontSize: 9, color: _muted)),
          heading('Where applicants found the job'),
          if (sources.isEmpty)
            pw.Text('No applications yet.', style: const pw.TextStyle(fontSize: 9.5, color: _muted))
          else
            bars([for (final s in sources) (s.key.label, s.value)]),
          heading('Speed'),
          pw.Text(
            [
              '${r.replied} of ${r.applications} applicants had a reply (stage change or message).',
              if (r.medianReplyHours != null) 'Typical time to first reply: ${replyTimeText(r.medianReplyHours)}.',
              if (r.firstHireDays != null) 'First hire ${r.firstHireDays!.round()} days after the job was posted.',
            ].join(' '),
            style: const pw.TextStyle(fontSize: 10, color: _ink),
          ),
          if (r.invitesSent > 0) ...[
            heading('Talent search'),
            pw.Text('${r.invitesSent} people invited to apply; ${r.invitedApplied} of them applied.', style: const pw.TextStyle(fontSize: 10, color: _ink)),
          ],
        ],
        pw.SizedBox(height: 16),
        pw.Text(
          'Figures come from Vocation SL records for this job. "Where applicants found the job" is recorded from app version 1.2; '
          'earlier applications show as not recorded. Views count each time the job page was opened.',
          style: const pw.TextStyle(fontSize: 8.5, color: _muted),
        ),
      ],
    ));
    return doc.save();
  }
}
