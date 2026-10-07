import '../models/models.dart';

/// Pure calculations behind the employer dashboard and insights screens.
class HiringStats {
  HiringStats({required this.jobs, required this.applications, DateTime? now}) : now = now ?? DateTime.now();

  final List<Job> jobs;
  final List<JobApplication> applications;
  final DateTime now;

  int get liveJobs => jobs.where((j) => j.status == JobStatus.published && !j.isClosed).length;
  int get pendingJobs => jobs.where((j) => j.status == JobStatus.pending).length;
  int get draftJobs => jobs.where((j) => j.status == JobStatus.draft).length;

  int get totalApplicants => applications.where((a) => a.status != ApplicationStatus.withdrawn).length;
  int get newThisWeek => applications.where((a) => now.difference(a.submittedAt).inDays < 7).length;
  int get awaitingReview => applications.where((a) => a.status == ApplicationStatus.applied).length;
  int get totalViews => jobs.fold(0, (s, j) => s + j.views);

  List<JobApplication> get upcomingInterviews => applications
      .where((a) => a.status == ApplicationStatus.interview && a.interviewAt != null && a.interviewAt!.isAfter(now))
      .toList()
    ..sort((a, b) => a.interviewAt!.compareTo(b.interviewAt!));

  int get hires => applications.where((a) => a.status == ApplicationStatus.hired).length;

  /// How many candidates reached each pipeline stage (counting anyone who
  /// passed through it, not just those currently in it).
  Map<ApplicationStatus, int> get funnel {
    final result = {for (final s in ApplicationStatus.pipeline) s: 0};
    for (final a in applications) {
      final reached = {a.status, ...a.history.map((e) => e.status)};
      var furthest = -1;
      for (var i = 0; i < ApplicationStatus.pipeline.length; i++) {
        if (reached.contains(ApplicationStatus.pipeline[i])) furthest = i;
      }
      for (var i = 0; i <= furthest; i++) {
        result[ApplicationStatus.pipeline[i]] = result[ApplicationStatus.pipeline[i]]! + 1;
      }
    }
    return result;
  }

  /// Current status counts (including rejected and withdrawn).
  Map<ApplicationStatus, int> get byStatus {
    final result = {for (final s in ApplicationStatus.values) s: 0};
    for (final a in applications) {
      result[a.status] = result[a.status]! + 1;
    }
    return result;
  }

  /// Applications per day for the last [days] days, oldest first.
  List<({DateTime day, int count})> dailyApplications({int days = 30}) {
    final start = DateTime(now.year, now.month, now.day).subtract(Duration(days: days - 1));
    final counts = List<int>.filled(days, 0);
    for (final a in applications) {
      final d = DateTime(a.submittedAt.year, a.submittedAt.month, a.submittedAt.day);
      final i = d.difference(start).inDays;
      if (i >= 0 && i < days) counts[i]++;
    }
    return [for (var i = 0; i < days; i++) (day: start.add(Duration(days: i)), count: counts[i])];
  }

  /// Average days from application to the employer's first action.
  double? get averageResponseDays {
    final waits = <double>[];
    for (final a in applications) {
      final firstAction = a.history.where((e) => e.status != ApplicationStatus.applied && e.status != ApplicationStatus.withdrawn).firstOrNull;
      if (firstAction != null) waits.add(firstAction.at.difference(a.submittedAt).inHours / 24);
    }
    if (waits.isEmpty) return null;
    return waits.reduce((a, b) => a + b) / waits.length;
  }

  /// Per-job performance, most applicants first.
  List<JobPerformance> get jobPerformance {
    final list = [
      for (final j in jobs.where((j) => j.status != JobStatus.draft))
        JobPerformance(
          job: j,
          applicants: applications.where((a) => a.jobId == j.id && a.status != ApplicationStatus.withdrawn).length,
          shortlisted: applications
              .where((a) => a.jobId == j.id && {a.status, ...a.history.map((e) => e.status)}.contains(ApplicationStatus.shortlisted))
              .length,
          hired: applications.where((a) => a.jobId == j.id && a.status == ApplicationStatus.hired).length,
        ),
    ]..sort((a, b) => b.applicants.compareTo(a.applicants));
    return list;
  }
}

class JobPerformance {
  const JobPerformance({required this.job, required this.applicants, required this.shortlisted, required this.hired});
  final Job job;
  final int applicants;
  final int shortlisted;
  final int hired;

  int get views => job.views;

  /// Share of viewers who applied, or null when there are no views yet.
  double? get conversion => job.views == 0 ? null : applicants / job.views;
}
