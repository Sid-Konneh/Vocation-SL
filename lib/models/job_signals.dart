import 'hiring.dart';
import 'job.dart';

/// Short, honest prompts on a job page: how many have applied, and whether the
/// employer usually replies. Every line comes from real counts.
abstract final class JobSignals {
  /// Below this many applicants, an applicant still counts as early.
  static const earlyUntil = 10;

  /// External jobs count as new for this long (we can't see how many applied).
  static const newFor = Duration(days: 3);

  /// "Be the first to apply", "Be an early applicant: 3 people have applied",
  /// "24 people have applied", or null when there is nothing useful to say.
  static String? momentum(Job j, {DateTime? now}) {
    final t = now ?? DateTime.now();
    if (j.status != JobStatus.published || !j.deadline.isAfter(t)) return null;
    if (j.appliesExternally) {
      // Applications go to the employer, so we only know when it was posted.
      return t.difference(j.postedAt) <= newFor ? 'New: be one of the first to apply' : null;
    }
    final n = j.applicants;
    if (n == 0) return 'Be the first to apply';
    final people = n == 1 ? '1 person has' : '$n people have';
    return n < earlyUntil ? 'Be an early applicant: $people applied' : '$people applied';
  }

  /// "Responsive employer": enough replies to judge, most applicants hear
  /// back, and the usual reply comes within a week.
  static bool isResponsive(ReplySpeed s) =>
      s.hasEnoughData && s.replyRate >= 0.6 && (s.medianHours ?? double.infinity) <= 7 * 24;

  /// e.g. "Usually replies in about 2 days".
  static String responsiveLabel(ReplySpeed s) => 'Usually replies ${s.typical}';
}
