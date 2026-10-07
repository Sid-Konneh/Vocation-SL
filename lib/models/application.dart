import 'documents.dart';
import 'job.dart';

enum ApplicationStatus {
  applied('Applied', 'Your application was sent to the employer.'),
  viewed('Application viewed', 'The employer opened your application.'),
  shortlisted('Shortlisted', 'You made the shortlist for this role.'),
  assessment('Assessment', 'The employer has asked you to complete an assessment.'),
  interview('Interview', 'You have been invited to interview.'),
  offer('Offer', 'The employer has made you an offer.'),
  hired('Hired', 'Congratulations, you got the job.'),
  rejected('Not selected', 'The employer decided not to move forward.'),
  withdrawn('Withdrawn', 'You withdrew this application.');

  const ApplicationStatus(this.label, this.description);
  final String label;
  final String description;

  bool get isClosed => this == hired || this == rejected || this == withdrawn;
  bool get isActive => !isClosed;

  /// The normal hiring pipeline, used to draw the progress timeline.
  static const pipeline = [applied, viewed, shortlisted, assessment, interview, offer, hired];

  static ApplicationStatus fromName(Object? n) =>
      ApplicationStatus.values.firstWhere((s) => s.name == n, orElse: () => ApplicationStatus.applied);
}

class StatusEvent {
  const StatusEvent({required this.status, required this.at, this.note});
  final ApplicationStatus status;
  final DateTime at;
  final String? note;

  factory StatusEvent.fromJson(Map<String, dynamic> j) => StatusEvent(
        status: ApplicationStatus.fromName(j['status']),
        at: DateTime.parse(j['at'] as String),
        note: j['note'] as String?,
      );

  Map<String, dynamic> toJson() => {'status': status.name, 'at': at.toIso8601String(), 'note': note};
}

class ApplicantInfo {
  const ApplicantInfo({required this.fullName, required this.email, required this.phone, required this.location});
  final String fullName;
  final String email;
  final String phone;
  final String location;

  factory ApplicantInfo.fromJson(Map<String, dynamic> j) => ApplicantInfo(
        fullName: j['full_name'] as String? ?? '',
        email: j['email'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        location: j['location'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'full_name': fullName, 'email': email, 'phone': phone, 'location': location};
}

class JobApplication {
  const JobApplication({
    required this.id,
    required this.jobId,
    required this.userId,
    required this.status,
    required this.submittedAt,
    required this.history,
    required this.applicant,
    required this.resume,
    this.coverLetter,
    this.note,
    this.interviewAt,
    this.nextStepDeadline,
    this.employerMessage,
    this.pendingSync = false,
    this.job,
  });

  final String id;
  final String jobId;
  final String userId;
  final ApplicationStatus status;
  final DateTime submittedAt;
  final List<StatusEvent> history;
  final ApplicantInfo applicant;
  final Resume resume;
  final CoverLetter? coverLetter;
  final String? note;
  final DateTime? interviewAt;
  final DateTime? nextStepDeadline;
  final String? employerMessage;

  /// True while the submission is waiting in the offline outbox.
  final bool pendingSync;
  final Job? job;

  DateTime get updatedAt => history.isEmpty ? submittedAt : history.last.at;

  JobApplication copyWith({
    ApplicationStatus? status,
    List<StatusEvent>? history,
    DateTime? Function()? interviewAt,
    DateTime? Function()? nextStepDeadline,
    String? Function()? employerMessage,
    bool? pendingSync,
    Job? Function()? job,
  }) =>
      JobApplication(
        id: id,
        jobId: jobId,
        userId: userId,
        status: status ?? this.status,
        submittedAt: submittedAt,
        history: history ?? this.history,
        applicant: applicant,
        resume: resume,
        coverLetter: coverLetter,
        note: note,
        interviewAt: interviewAt != null ? interviewAt() : this.interviewAt,
        nextStepDeadline: nextStepDeadline != null ? nextStepDeadline() : this.nextStepDeadline,
        employerMessage: employerMessage != null ? employerMessage() : this.employerMessage,
        pendingSync: pendingSync ?? this.pendingSync,
        job: job != null ? job() : this.job,
      );

  factory JobApplication.fromJson(Map<String, dynamic> j) => JobApplication(
        id: j['id'] as String,
        jobId: j['job_id'] as String,
        userId: j['user_id'] as String,
        status: ApplicationStatus.fromName(j['status']),
        submittedAt: DateTime.parse(j['submitted_at'] as String),
        history: [
          for (final e in (j['history'] as List? ?? const [])) StatusEvent.fromJson(Map<String, dynamic>.from(e as Map))
        ],
        applicant: ApplicantInfo.fromJson(Map<String, dynamic>.from(j['applicant'] as Map? ?? const {})),
        resume: Resume.fromJson(Map<String, dynamic>.from(j['resume'] as Map)),
        coverLetter: j['cover_letter'] == null
            ? null
            : CoverLetter.fromJson(Map<String, dynamic>.from(j['cover_letter'] as Map)),
        note: j['note'] as String?,
        interviewAt: j['interview_at'] == null ? null : DateTime.parse(j['interview_at'] as String),
        nextStepDeadline: j['next_step_deadline'] == null ? null : DateTime.parse(j['next_step_deadline'] as String),
        employerMessage: j['employer_message'] as String?,
        pendingSync: j['pending_sync'] as bool? ?? false,
        job: j['job'] is Map ? Job.fromJson(Map<String, dynamic>.from(j['job'] as Map)) : null,
      );

  Map<String, dynamic> toJson({bool includeJob = false, bool includeLocal = true}) => {
        'id': id,
        'job_id': jobId,
        'user_id': userId,
        'status': status.name,
        'submitted_at': submittedAt.toIso8601String(),
        'history': history.map((e) => e.toJson()).toList(),
        'applicant': applicant.toJson(),
        'resume': resume.toJson(),
        'cover_letter': coverLetter?.toJson(),
        'note': note,
        'interview_at': interviewAt?.toIso8601String(),
        'next_step_deadline': nextStepDeadline?.toIso8601String(),
        'employer_message': employerMessage,
        if (includeLocal) 'pending_sync': pendingSync,
        if (includeJob && job != null) 'job': job!.toJson(),
      };
}
