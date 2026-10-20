import 'dart:convert';
import 'dart:typed_data';

import 'package:share_plus/share_plus.dart';

import '../core/platform/download.dart';

/// Builds CSV files (they open in Excel and Google Sheets) and hands them to
/// the user: a download in the browser, the share/save sheet on phones.
class ExportService {
  static String csv(List<String> header, List<List<Object?>> rows) {
    String cell(Object? v) {
      final s = v == null ? '' : '$v';
      return RegExp(r'[",\n\r]').hasMatch(s) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    return [header, ...rows].map((r) => r.map(cell).join(',')).join('\r\n');
  }

  static Future<void> save(String fileName, String content) async {
    // A byte-order mark so Excel reads "Le" and accented names correctly.
    final bytes = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode(content)]);
    if (downloadSupported) {
      downloadBytes(fileName, bytes, 'text/csv');
      return;
    }
    await SharePlus.instance.share(ShareParams(files: [XFile.fromData(bytes, name: fileName, mimeType: 'text/csv')], fileNameOverrides: [fileName]));
  }
}
