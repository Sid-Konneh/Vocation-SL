import 'job.dart';
import 'job_filter.dart';

class SavedJob {
  const SavedJob({required this.jobId, required this.userId, required this.savedAt, this.job});
  final String jobId;
  final String userId;
  final DateTime savedAt;
  final Job? job;

  SavedJob withJob(Job? j) => SavedJob(jobId: jobId, userId: userId, savedAt: savedAt, job: j);

  factory SavedJob.fromJson(Map<String, dynamic> j) => SavedJob(
        jobId: j['job_id'] as String,
        userId: j['user_id'] as String,
        savedAt: DateTime.parse(j['saved_at'] as String),
      );

  Map<String, dynamic> toJson() => {'job_id': jobId, 'user_id': userId, 'saved_at': savedAt.toIso8601String()};
}

enum AlertFrequency {
  instant('Instantly'),
  daily('Daily'),
  weekly('Weekly');

  const AlertFrequency(this.label);
  final String label;
}

/// A saved search that notifies the user about new matching jobs.
class JobAlert {
  const JobAlert({
    required this.id,
    required this.userId,
    required this.name,
    required this.filter,
    required this.createdAt,
    this.enabled = true,
    this.frequency = AlertFrequency.daily,
    this.lastCheckedAt,
  });

  final String id;
  final String userId;
  final String name;
  final JobFilter filter;
  final DateTime createdAt;
  final bool enabled;
  final AlertFrequency frequency;
  final DateTime? lastCheckedAt;

  JobAlert copyWith({String? name, bool? enabled, AlertFrequency? frequency, DateTime? lastCheckedAt}) => JobAlert(
        id: id,
        userId: userId,
        name: name ?? this.name,
        filter: filter,
        createdAt: createdAt,
        enabled: enabled ?? this.enabled,
        frequency: frequency ?? this.frequency,
        lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      );

  factory JobAlert.fromJson(Map<String, dynamic> j) => JobAlert(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        name: j['name'] as String? ?? 'Saved search',
        filter: JobFilter.fromJson(Map<String, dynamic>.from(j['filter'] as Map? ?? const {})),
        createdAt: DateTime.parse(j['created_at'] as String),
        enabled: j['enabled'] as bool? ?? true,
        frequency: AlertFrequency.values.firstWhere((f) => f.name == j['frequency'], orElse: () => AlertFrequency.daily),
        lastCheckedAt: j['last_checked_at'] == null ? null : DateTime.parse(j['last_checked_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'filter': filter.toJson(),
        'created_at': createdAt.toIso8601String(),
        'enabled': enabled,
        'frequency': frequency.name,
        'last_checked_at': lastCheckedAt?.toIso8601String(),
      };
}
