import 'enums.dart';

DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v')?.toLocal();
int _int(Object? v) => (v as num?)?.toInt() ?? 0;
double? _double(Object? v) => (v as num?)?.toDouble();

// ---- Interview time slots -------------------------------------------------------

enum InterviewProposalStatus { open, chosen, cancelled }

/// Up to 3 interview times an employer offered; the applicant picks one.
class InterviewProposal {
  const InterviewProposal({
    required this.id,
    required this.applicationId,
    required this.slots,
    required this.status,
    required this.createdAt,
    this.place = '',
    this.note = '',
    this.chosenAt,
  });

  final String id;
  final String applicationId;
  final List<DateTime> slots;
  final InterviewProposalStatus status;
  final DateTime createdAt;
  final String place;
  final String note;
  final DateTime? chosenAt;

  bool get isOpen => status == InterviewProposalStatus.open;
  bool get isChosen => status == InterviewProposalStatus.chosen && chosenAt != null;

  /// Offered times that haven't passed yet.
  List<DateTime> upcomingSlots([DateTime? now]) => slots.where((s) => s.isAfter(now ?? DateTime.now())).toList();

  factory InterviewProposal.fromJson(Map<String, dynamic> j) => InterviewProposal(
        id: '${j['id']}',
        applicationId: j['application_id'] as String,
        slots: [for (final s in (j['slots'] as List? ?? const [])) ?_date(s)]..sort(),
        status: enumByName(InterviewProposalStatus.values, j['status'], InterviewProposalStatus.open),
        createdAt: _date(j['created_at']) ?? DateTime.now(),
        place: j['place'] as String? ?? '',
        note: j['note'] as String? ?? '',
        chosenAt: _date(j['chosen_at']),
      );
}

// ---- Employer reply speed --------------------------------------------------------

/// How quickly an employer usually replies to applicants (last 6 months).
class ReplySpeed {
  const ReplySpeed({required this.applications, required this.replied, this.medianHours, this.repliedWithin7Days = 0});

  final int applications;
  final int replied;
  final double? medianHours;
  final int repliedWithin7Days;

  static const unknown = ReplySpeed(applications: 0, replied: 0);

  /// Fewer replies than this and the figure would mislead.
  static const minSample = 3;

  bool get hasEnoughData => replied >= minSample && medianHours != null;

  /// e.g. "about 2 days", "within a day".
  String get typical {
    final h = medianHours;
    if (h == null) return '';
    if (h < 24) return 'within a day';
    final d = (h / 24).round();
    if (d < 14) return 'in about $d day${d == 1 ? '' : 's'}';
    final w = (d / 7).round();
    return 'in about $w weeks';
  }

  double get replyRate => applications == 0 ? 0 : replied / applications;

  factory ReplySpeed.fromJson(Map<String, dynamic> j) => ReplySpeed(
        applications: _int(j['applications']),
        replied: _int(j['replied']),
        medianHours: _double(j['median_hours']),
        repliedWithin7Days: _int(j['replied_within_7_days']),
      );
}

// ---- Talent search ---------------------------------------------------------------

/// The summary an employer sees in talent search. Contact details are not
/// included; the person shares them by applying.
class TalentProfile {
  const TalentProfile({
    required this.userId,
    required this.fullName,
    this.headline = '',
    this.location = '',
    this.about = '',
    this.skills = const [],
    this.experience = const [],
    this.education = const [],
    this.languages = const [],
    this.updatedAt,
    this.invitedJobIds = const [],
  });

  final String userId;
  final String fullName;
  final String headline;
  final String location;
  final String about;
  final List<String> skills;

  /// e.g. "Accountant · Sierra Rutile (2021 – now)".
  final List<String> experience;

  /// e.g. "BSc Accounting, Fourah Bay College (2020)".
  final List<String> education;
  final List<String> languages;
  final DateTime? updatedAt;
  final List<String> invitedJobIds;

  String get initials {
    final p = fullName.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (p.isEmpty) return '?';
    return p.length > 1 ? '${p.first[0]}${p.last[0]}'.toUpperCase() : p.first[0].toUpperCase();
  }

  TalentProfile withInvite(String jobId) => TalentProfile(
        userId: userId,
        fullName: fullName,
        headline: headline,
        location: location,
        about: about,
        skills: skills,
        experience: experience,
        education: education,
        languages: languages,
        updatedAt: updatedAt,
        invitedJobIds: [...invitedJobIds, jobId],
      );

  static String _year(Object? v) {
    final d = _date(v);
    return d == null ? '' : '${d.year}';
  }

  factory TalentProfile.fromJson(Map<String, dynamic> j) => TalentProfile(
        userId: '${j['user_id']}',
        fullName: j['full_name'] as String? ?? '',
        headline: j['headline'] as String? ?? '',
        location: j['location'] as String? ?? '',
        about: j['about'] as String? ?? '',
        skills: [for (final s in (j['skills'] as List? ?? const [])) '$s'],
        experience: [
          for (final e in (j['experience'] as List? ?? const []).whereType<Map>())
            [
              [e['title'], e['company']].where((s) => '${s ?? ''}'.trim().isNotEmpty).join(' · '),
              if (_year(e['start']).isNotEmpty) '(${_year(e['start'])} – ${e['end'] == null ? 'now' : _year(e['end'])})',
            ].join(' '),
        ],
        education: [
          for (final e in (j['education'] as List? ?? const []).whereType<Map>())
            [
              [e['degree'], e['field']].where((s) => '${s ?? ''}'.trim().isNotEmpty).join(' '),
              if ('${e['school'] ?? ''}'.isNotEmpty) ', ${e['school']}',
              if (e['end_year'] != null) ' (${e['end_year']})',
            ].join(),
        ],
        languages: [
          for (final l in (j['languages'] as List? ?? const []).whereType<Map>())
            [l['name'], if ('${l['level'] ?? ''}'.isNotEmpty) '(${l['level']})'].join(' '),
        ],
        updatedAt: _date(j['updated_at']),
        invitedJobIds: [for (final id in (j['invited_jobs'] as List? ?? const [])) '$id'],
      );
}

// ---- Where applicants found the job -----------------------------------------------

/// Recorded on each application (from 1.2) for the employer's hiring report.
enum ApplicationSource {
  home('Browsing jobs'),
  featured('Featured jobs'),
  search('Search'),
  saved('Saved jobs'),
  company('Company page'),
  alert('Job alerts'),
  invite('Talent search invitation'),
  link('Shared link or website'),
  app('Elsewhere in the app'),
  unknown('Not recorded (before 1.2)');

  const ApplicationSource(this.label);
  final String label;

  static ApplicationSource fromName(Object? n) => enumByName(values, n, unknown);
}

// ---- Hiring report ------------------------------------------------------------------

class JobReport {
  const JobReport({
    required this.jobId,
    required this.title,
    required this.status,
    required this.location,
    required this.postedAt,
    required this.deadline,
    required this.views,
    required this.applyClicks,
    required this.appliesExternally,
    required this.applications,
    required this.withdrawn,
    required this.current,
    required this.reached,
    required this.sources,
    required this.invitesSent,
    required this.invitedApplied,
    required this.replied,
    required this.byDay,
    required this.generatedAt,
    this.medianReplyHours,
    this.firstHireDays,
  });

  final String jobId;
  final String title;
  final String status;
  final String location;
  final DateTime? postedAt;
  final DateTime? deadline;
  final int views;
  final int applyClicks;
  final bool appliesExternally;
  final int applications;
  final int withdrawn;

  /// Applications by current stage name.
  final Map<String, int> current;

  /// How many reached each stage: shortlisted, interview, offer, hired.
  final Map<String, int> reached;
  final Map<ApplicationSource, int> sources;
  final int invitesSent;
  final int invitedApplied;
  final int replied;
  final double? medianReplyHours;
  final double? firstHireDays;
  final List<({DateTime day, int count})> byDay;
  final DateTime generatedAt;

  int get hired => reached['hired'] ?? 0;

  /// Applications per 100 views (null when there are no views yet).
  double? get conversion => views == 0 ? null : applications * 100 / views;

  factory JobReport.fromJson(Map<String, dynamic> j) {
    final src = <ApplicationSource, int>{};
    for (final e in Map<String, dynamic>.from(j['sources'] as Map? ?? const {}).entries) {
      final s = ApplicationSource.fromName(e.key);
      src[s] = (src[s] ?? 0) + _int(e.value);
    }
    return JobReport(
      jobId: '${j['job_id']}',
      title: j['title'] as String? ?? '',
      status: j['status'] as String? ?? '',
      location: j['location'] as String? ?? '',
      postedAt: _date(j['posted_at']),
      deadline: _date(j['deadline']),
      views: _int(j['views']),
      applyClicks: _int(j['apply_clicks']),
      appliesExternally: j['applies_externally'] as bool? ?? false,
      applications: _int(j['applications']),
      withdrawn: _int(j['withdrawn']),
      current: {for (final e in Map<String, dynamic>.from(j['current'] as Map? ?? const {}).entries) e.key: _int(e.value)},
      reached: {for (final e in Map<String, dynamic>.from(j['reached'] as Map? ?? const {}).entries) e.key: _int(e.value)},
      sources: src,
      invitesSent: _int(j['invites_sent']),
      invitedApplied: _int(j['invited_applied']),
      replied: _int(j['replied']),
      medianReplyHours: _double(j['median_reply_hours']),
      firstHireDays: _double(j['first_hire_days']),
      byDay: [
        for (final d in (j['by_day'] as List? ?? const []).whereType<Map>())
          if (_date(d['day']) != null) (day: _date(d['day'])!, count: _int(d['n'])),
      ],
      generatedAt: _date(j['generated_at']) ?? DateTime.now(),
    );
  }
}

// ---- Support inbox --------------------------------------------------------------------

enum SupportCategory {
  account('My account'),
  jobs('Finding jobs'),
  applications('My applications'),
  employer('Posting jobs and hiring'),
  payment('Invoices and payments'),
  scam('Report a scam or fake job'),
  bug('Something isn\'t working'),
  other('Something else');

  const SupportCategory(this.label);
  final String label;
}

enum SupportStatus {
  open('Waiting for us'),
  answered('Answered'),
  closed('Closed');

  const SupportStatus(this.label);
  final String label;
}

class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.userId,
    required this.subject,
    required this.category,
    required this.status,
    required this.createdAt,
    required this.lastMessageAt,
    this.side = UserRole.seeker,
    this.userName = '',
    this.userEmail = '',
  });

  final String id;
  final String userId;
  final String subject;
  final SupportCategory category;
  final SupportStatus status;
  final DateTime createdAt;
  final DateTime lastMessageAt;
  final UserRole side;

  /// Filled in for the admin inbox.
  final String userName;
  final String userEmail;

  SupportTicket copyWith({SupportStatus? status, DateTime? lastMessageAt}) => SupportTicket(
        id: id,
        userId: userId,
        subject: subject,
        category: category,
        status: status ?? this.status,
        createdAt: createdAt,
        lastMessageAt: lastMessageAt ?? this.lastMessageAt,
        side: side,
        userName: userName,
        userEmail: userEmail,
      );

  factory SupportTicket.fromJson(Map<String, dynamic> j) => SupportTicket(
        id: '${j['id']}',
        userId: '${j['user_id']}',
        subject: j['subject'] as String? ?? '',
        category: enumByName(SupportCategory.values, j['category'], SupportCategory.other),
        status: enumByName(SupportStatus.values, j['status'], SupportStatus.open),
        createdAt: _date(j['created_at']) ?? DateTime.now(),
        lastMessageAt: _date(j['last_message_at']) ?? _date(j['created_at']) ?? DateTime.now(),
        side: j['side'] == 'employer' ? UserRole.employer : UserRole.seeker,
        userName: j['user_name'] as String? ?? '',
        userEmail: j['user_email'] as String? ?? '',
      );
}

class SupportMessage {
  const SupportMessage({required this.id, required this.ticketId, required this.fromStaff, required this.body, required this.createdAt});
  final String id;
  final String ticketId;
  final bool fromStaff;
  final String body;
  final DateTime createdAt;

  factory SupportMessage.fromJson(Map<String, dynamic> j) => SupportMessage(
        id: '${j['id']}',
        ticketId: '${j['ticket_id']}',
        fromStaff: j['from_staff'] as bool? ?? false,
        body: j['body'] as String? ?? '',
        createdAt: _date(j['created_at']) ?? DateTime.now(),
      );
}

// ---- Weekly admin digest ------------------------------------------------------------------

class WeeklyDigest {
  const WeeklyDigest(this.values);
  final Map<String, dynamic> values;

  /// A count or amount (amounts rounded to whole leones).
  int n(String key) => ((values[key] as num?) ?? 0).round();
  DateTime? get from => _date(values['from']);
  DateTime? get to => _date(values['to']);
  List<String> get newEmployerNames => [for (final s in (values['new_employer_names'] as List? ?? const [])) '$s'];
}
