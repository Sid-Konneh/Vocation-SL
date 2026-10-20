import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../core/errors.dart';
import '../models/models.dart';

/// Builds a clean one- or two-page CV (PDF) from the job seeker's profile, so
/// people without a PDF CV can still apply (applications accept PDF only).
class CvPdf {
  static const _green = PdfColor.fromInt(0xFF3F7A1F);
  static const _ink = PdfColor.fromInt(0xFF14171A);
  static const _muted = PdfColor.fromInt(0xFF5E6670);
  static const _line = PdfColor.fromInt(0xFFE3E7E0);

  /// What's missing before a useful CV can be made ('' when ready).
  static String missing(AppUser u) {
    if (u.fullName.trim().isEmpty) return 'Add your name to your profile first.';
    if (u.phone.trim().isEmpty && u.email.trim().isEmpty) return 'Add a phone number or email to your profile first.';
    if (u.experience.isEmpty && u.education.isEmpty && u.skills.isEmpty) {
      return 'Add your experience, education or skills to your profile first.';
    }
    return '';
  }

  /// File name used when the CV is saved, e.g. "Aminata Sesay CV.pdf".
  static String fileName(AppUser u) => '${u.fullName.trim().isEmpty ? 'My' : u.fullName.trim()} CV.pdf';

  static Future<Uint8List> build(AppUser u) async {
    final problem = missing(u);
    if (problem.isNotEmpty) throw ValidationException(problem);

    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/PlusJakartaSans-400.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/PlusJakartaSans-700.ttf'));
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);
    final month = DateFormat('MMM yyyy');

    pw.ImageProvider? photo;
    if (u.photoBase64 != null) {
      try {
        photo = pw.MemoryImage(base64Decode(u.photoBase64!));
      } catch (_) {
        photo = null;
      }
    }

    pw.Widget heading(String t) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Text(t.toUpperCase(), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _green, letterSpacing: 1.2)),
            pw.SizedBox(height: 3),
            pw.Container(height: 0.8, color: _line),
          ]),
        );

    pw.Widget entry(String title, String sub, String when, [String body = '']) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Expanded(child: pw.Text(title, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _ink))),
              pw.Text(when, style: const pw.TextStyle(fontSize: 9, color: _muted)),
            ]),
            if (sub.isNotEmpty) pw.Text(sub, style: const pw.TextStyle(fontSize: 10, color: _muted)),
            if (body.trim().isNotEmpty) pw.Padding(padding: const pw.EdgeInsets.only(top: 3), child: pw.Text(body.trim(), style: const pw.TextStyle(fontSize: 10, color: _ink, lineSpacing: 2))),
          ]),
        );

    final contact = [
      if (u.phone.trim().isNotEmpty) u.phone.trim(),
      if (u.email.trim().isNotEmpty) u.email.trim(),
      if (u.location.trim().isNotEmpty) '${u.location.trim()}, Sierra Leone',
    ].join('  ·  ');
    final links = [if (u.linkedinUrl.trim().isNotEmpty) u.linkedinUrl.trim(), if (u.portfolioUrl.trim().isNotEmpty) u.portfolioUrl.trim()].join('  ·  ');

    final doc = pw.Document(title: '${u.fullName} CV', author: u.fullName, creator: 'Vocation SL');
    doc.addPage(pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(40, 36, 40, 36),
      footer: (c) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text('${u.fullName} · page ${c.pageNumber} of ${c.pagesCount}', style: const pw.TextStyle(fontSize: 8, color: _muted)),
      ),
      build: (c) => [
        pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
          if (photo != null) ...[
            pw.ClipOval(child: pw.Container(width: 64, height: 64, child: pw.Image(photo, fit: pw.BoxFit.cover))),
            pw.SizedBox(width: 14),
          ],
          pw.Expanded(
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text(u.fullName.trim(), style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: _ink)),
              if (u.headline.trim().isNotEmpty) pw.Text(u.headline.trim(), style: const pw.TextStyle(fontSize: 12, color: _green)),
              pw.SizedBox(height: 4),
              if (contact.isNotEmpty) pw.Text(contact, style: const pw.TextStyle(fontSize: 9.5, color: _muted)),
              if (links.isNotEmpty) pw.Text(links, style: const pw.TextStyle(fontSize: 9.5, color: _muted)),
            ]),
          ),
        ]),
        if (u.about.trim().isNotEmpty) ...[heading('Profile'), pw.Text(u.about.trim(), style: const pw.TextStyle(fontSize: 10, color: _ink, lineSpacing: 2))],
        if (u.experience.isNotEmpty) ...[
          heading('Experience'),
          for (final e in u.experience)
            entry(e.title, [e.company, e.location].where((s) => s.trim().isNotEmpty).join(', '),
                '${month.format(e.start)} – ${e.end == null ? 'Present' : month.format(e.end!)}', e.description),
        ],
        if (u.education.isNotEmpty) ...[
          heading('Education'),
          for (final e in u.education)
            entry(e.school, [e.degree, e.field].where((s) => s.trim().isNotEmpty).join(', '), '${e.startYear} – ${e.endYear ?? 'Present'}'),
        ],
        if (u.skills.isNotEmpty) ...[
          heading('Skills'),
          pw.Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in u.skills)
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: pw.BoxDecoration(color: const PdfColor.fromInt(0xFFEFF6E6), borderRadius: pw.BorderRadius.circular(8)),
                child: pw.Text(s, style: const pw.TextStyle(fontSize: 9.5, color: _ink)),
              ),
          ]),
        ],
        if (u.certifications.isNotEmpty) ...[
          heading('Certifications'),
          for (final c in u.certifications) entry(c.name, c.issuer, '${c.year}'),
        ],
        if (u.languages.isNotEmpty) ...[
          heading('Languages'),
          pw.Text(u.languages.map((l) => '${l.name} (${l.level})').join('  ·  '), style: const pw.TextStyle(fontSize: 10, color: _ink)),
        ],
      ],
    ));
    return doc.save();
  }
}
