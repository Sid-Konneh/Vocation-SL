enum NotificationType {
  newMatch('New matching job'),
  savedSearch('Saved search alert'),
  submitted('Application submitted'),
  viewed('Application viewed'),
  shortlisted('Shortlisted'),
  interview('Interview'),
  statusChange('Status update'),
  message('Employer message'),
  deadline('Deadline reminder'),
  newApplicant('New applicant');

  const NotificationType(this.label);
  final String label;
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.read = false,
    this.jobId,
    this.applicationId,
  });

  final String id;
  final String userId;
  final NotificationType type;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool read;
  final String? jobId;
  final String? applicationId;

  AppNotification copyWith({bool? read}) => AppNotification(
        id: id,
        userId: userId,
        type: type,
        title: title,
        body: body,
        createdAt: createdAt,
        read: read ?? this.read,
        jobId: jobId,
        applicationId: applicationId,
      );

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        type: NotificationType.values.firstWhere((t) => t.name == j['type'], orElse: () => NotificationType.statusChange),
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        createdAt: DateTime.parse(j['created_at'] as String),
        read: j['read'] as bool? ?? false,
        jobId: j['job_id'] as String?,
        applicationId: j['application_id'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'type': type.name,
        'title': title,
        'body': body,
        'created_at': createdAt.toIso8601String(),
        'read': read,
        'job_id': jobId,
        'application_id': applicationId,
      };
}

/// Which notification types the user wants to receive.
class NotificationPreferences {
  const NotificationPreferences({
    this.enabled = const {
      NotificationType.newMatch: true,
      NotificationType.savedSearch: true,
      NotificationType.submitted: true,
      NotificationType.viewed: true,
      NotificationType.shortlisted: true,
      NotificationType.interview: true,
      NotificationType.statusChange: true,
      NotificationType.message: true,
      NotificationType.deadline: true,
    },
    this.pushEnabled = true,
    this.emailDigest = false,
  });

  final Map<NotificationType, bool> enabled;
  final bool pushEnabled;
  final bool emailDigest;

  bool allows(NotificationType t) => enabled[t] ?? true;

  NotificationPreferences toggle(NotificationType t, bool value) =>
      NotificationPreferences(enabled: {...enabled, t: value}, pushEnabled: pushEnabled, emailDigest: emailDigest);

  NotificationPreferences copyWith({bool? pushEnabled, bool? emailDigest}) => NotificationPreferences(
        enabled: enabled,
        pushEnabled: pushEnabled ?? this.pushEnabled,
        emailDigest: emailDigest ?? this.emailDigest,
      );

  factory NotificationPreferences.fromJson(Map<String, dynamic> j) {
    final raw = Map<String, dynamic>.from(j['enabled'] as Map? ?? const {});
    return NotificationPreferences(
      enabled: {for (final t in NotificationType.values) t: raw[t.name] as bool? ?? true},
      pushEnabled: j['push_enabled'] as bool? ?? true,
      emailDigest: j['email_digest'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'enabled': {for (final e in enabled.entries) e.key.name: e.value},
        'push_enabled': pushEnabled,
        'email_digest': emailDigest,
      };
}
