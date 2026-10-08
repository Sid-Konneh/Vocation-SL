import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:pdfrx/pdfrx.dart';

import '../core/errors.dart';
import '../models/models.dart';
import 'cv_parser.dart';

/// Reads a CV file on the device and returns the profile details found in it.
/// Nothing is sent to any online service.
Future<CvExtract> readCvOnDevice(Uint8List bytes, DocumentFormat? format) async {
  final text = switch (format) {
    DocumentFormat.pdf => await _pdfText(bytes),
    DocumentFormat.docx => _docxText(bytes),
    _ => throw const ValidationException('Only PDF and DOCX CVs can be read. Save your CV as a PDF and try again.'),
  };
  if (text.trim().length < 40) {
    throw const ValidationException(
      'We couldn\'t find text in this CV. If it is a scanned image, upload a PDF saved from Word or Google Docs instead.',
    );
  }
  return const CvParser().parse(text);
}

Future<String> _pdfText(Uint8List bytes) async {
  await pdfrxFlutterInitialize();
  final doc = await PdfDocument.openData(bytes);
  try {
    final buf = StringBuffer();
    for (final page in doc.pages.take(6)) {
      final t = await page.loadText();
      if (t != null) buf.writeln(t.fullText);
    }
    return buf.toString();
  } finally {
    await doc.dispose();
  }
}

String _docxText(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final file = archive.findFile('word/document.xml');
  if (file == null) return '';
  final xml = utf8.decode(file.content as List<int>, allowMalformed: true);
  return xml
      .replaceAll(RegExp(r'<w:tab/>'), '\t')
      .replaceAll(RegExp(r'</w:p>'), '\n')
      .replaceAll(RegExp(r'<w:br[^>]*/>'), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'");
}
