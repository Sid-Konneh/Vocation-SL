import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/utils/formatters.dart';
import '../models/models.dart';

class ShareService {
  String jobText(Job j) => '${j.title} at ${j.companyName}\n'
      '${j.location} · ${j.employmentType.label} · ${Fmt.salary(j)}\n'
      '${Fmt.deadline(j.deadline)}\n\n'
      'Found on Vocation SL.';

  /// Opens the system share sheet; falls back to copying the text.
  /// Returns true if the text was copied instead of shared.
  Future<bool> shareJob(Job j) async {
    final text = jobText(j);
    try {
      await SharePlus.instance.share(ShareParams(text: text, subject: '${j.title} – ${j.companyName}'));
      return false;
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    }
  }
}
