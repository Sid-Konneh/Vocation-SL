import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../core/config/app_config.dart';
import '../core/utils/formatters.dart';
import '../models/models.dart';

class ShareService {
  /// Opens the job straight away: in the Android app when it is installed,
  /// otherwise in the web app.
  static String jobLink(String jobId) => '${AppConfig.appUrl}/job/$jobId';

  String jobText(Job j) => '${j.title} at ${j.companyName}\n'
      '${j.location} · ${j.employmentType.label} · ${Fmt.salary(j)}\n'
      '${Fmt.deadline(j.deadline)}\n\n'
      'View and apply on Vocation SL:\n${jobLink(j.id)}';

  String referralText(String code) => 'Hiring? Post your jobs on Vocation SL and reach job seekers in all 16 districts of Sierra Leone. '
      'Applicants, CVs and messages are all in one place.\n\n'
      'Sign up with my referral link:\n${ReferralCode.link(code, base: AppConfig.employersUrl)}\n'
      'or enter my code ${ReferralCode.display(code)} when you create your company.';

  /// Opens the system share sheet; falls back to copying the text.
  /// Returns true if the text was copied instead of shared.
  Future<bool> shareJob(Job j) => shareText(jobText(j), subject: '${j.title} – ${j.companyName}');

  Future<bool> shareText(String text, {String? subject}) async {
    try {
      await SharePlus.instance.share(ShareParams(text: text, subject: subject));
      return false;
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: text));
      return true;
    }
  }
}
