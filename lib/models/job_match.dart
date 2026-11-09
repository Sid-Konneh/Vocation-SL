import 'enums.dart';
import 'job.dart';
import 'user.dart';

/// How well a job fits a job seeker's profile, with the reasons shown to them.
/// Combines AI and rules: the AI similarity between the meaning of the
/// profile and the job (from the server, see ai_match_providers.dart), plus
/// location, the words in their headline, past job titles, studies and
/// skills, and their job preferences (job type, industry, work mode, salary).
class JobMatch {
  const JobMatch(this.score, this.reasons);
  final int score;
  final List<String> reasons;

  /// Worth recommending: at least the same area or a shared title word.
  bool get isGood => score >= 3;

  /// AI similarity (0–1) from which a profile fits a job, and from which it
  /// fits strongly. Set on 8 Nov 2026 from 3,354 real profile–job pairs:
  /// 0.81 is about the top 25%, 0.84 about the top 5%.
  static const aiGood = 0.81;
  static const aiStrong = 0.84;

  /// Points the AI similarity adds to the score: 4 for a strong fit, 2 for a good one.
  static int aiPoints(double? ai) => ai == null ? 0 : ai >= aiStrong ? 4 : ai >= aiGood ? 2 : 0;

  /// Words for an AI similarity, for employers' applicant lists.
  static String aiLabel(double? ai) => ai == null ? '—' : ai >= aiStrong ? 'Strong' : ai >= aiGood ? 'Good' : 'Low';

  static const _stop = {
    'and', 'the', 'for', 'with', 'of', 'in', 'at', 'to', 'on', 'or', 'an', 'a', 'by', 'from', 'as',
    'sierra', 'leone', 'sl', 'job', 'jobs', 'position', 'positions', 'role', 'vacancy', 'work', 'new',
    'willing', 'learn', 'seeking', 'motivated', 'beginner', 'student', 'graduate', 'online', 'remote',
    'skills', 'experience', 'team', 'program', 'programme', 'project', 'positions)', 'etc',
  };
  // Common in many titles, so they count for less than a specific word.
  static const _generic = {
    'officer', 'manager', 'assistant', 'coordinator', 'senior', 'junior', 'lead', 'head', 'support',
    'specialist', 'expert', 'technical', 'field', 'general', 'deputy', 'chief', 'director', 'associate',
  };

  static Set<String> words(String s) => {
        for (final w in s.toLowerCase().split(RegExp(r'[^a-z0-9]+')))
          if (w.length >= 3 && !_stop.contains(w)) _stem(w),
      };

  static String _stem(String w) {
    if (w.length > 4 && w.endsWith('ies')) return '${w.substring(0, w.length - 3)}y';
    if (w.length > 4 && w.endsWith('s') && !w.endsWith('ss')) return w.substring(0, w.length - 1);
    return w;
  }

  static JobMatch of(Job job, AppUser user, {double? ai}) {
    var score = 0;
    final reasons = <String>[];
    final prefs = user.preferences;

    // AI: how close the meaning of the profile is to the job.
    final aiPts = aiPoints(ai);
    if (aiPts > 0) {
      score += aiPts;
      reasons.add(aiPts >= 4 ? 'AI: a strong fit with your profile' : 'AI: fits your profile');
    }

    // Location: the profile's town, or any preferred location, in the same area.
    final wanted = <String>{
      ...sameAreaAs(user.location),
      for (final l in prefs.locations) ...sameAreaAs(l),
    }.map((e) => e.toLowerCase()).toSet();
    if (wanted.contains(job.location.trim().toLowerCase())) {
      score += 3;
      reasons.add('In ${job.location}');
    }

    // Words shared by the job title/skills and the profile.
    final mine = <String>{
      ...words(user.headline),
      for (final e in user.experience) ...words(e.title),
      for (final e in user.education) ...words('${e.degree} ${e.field}'),
      for (final s in user.skills) ...words(s),
      for (final t in prefs.titles) ...words(t),
    };
    final theirs = {...words(job.title), for (final s in job.skills) ...words(s)};
    final shared = mine.intersection(theirs);
    var wordScore = 0;
    for (final w in shared) {
      wordScore += _generic.contains(w) ? 1 : 3;
    }
    if (wordScore > 0) {
      score += wordScore > 9 ? 9 : wordScore;
      final specific = shared.where((w) => !_generic.contains(w)).toList()..sort();
      final show = (specific.isNotEmpty ? specific : shared.toList()).take(3).join(', ');
      reasons.add('Matches your profile: $show');
    }

    if (prefs.employmentTypes.contains(job.employmentType)) {
      score += 2;
      reasons.add(job.employmentType.label);
    }
    if (prefs.industries.contains(job.industry)) {
      score += 2;
      reasons.add(job.industry.label);
    }
    if (prefs.workModes.contains(job.workMode)) score += 1;
    final pay = prefs.salaryExpectation;
    final top = job.salaryMax ?? job.salaryMin;
    if (pay != null && top != null && top >= pay) {
      score += 1;
      reasons.add('Pays what you want');
    }
    return JobMatch(score, reasons);
  }

  /// The best open matches for [user], best first.
  static List<Job> recommend(Iterable<Job> jobs, AppUser? user, {int limit = 5, Map<String, double> ai = const {}}) {
    if (user == null) return const [];
    final scored = [
      for (final j in jobs)
        if (!j.isClosed) (j, of(j, user, ai: ai[j.id]).score),
    ].where((e) => e.$2 >= 3).toList()
      ..sort((a, b) => b.$2 != a.$2 ? b.$2.compareTo(a.$2) : b.$1.postedAt.compareTo(a.$1.postedAt));
    return [for (final e in scored.take(limit)) e.$1];
  }
}
