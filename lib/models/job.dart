import 'company.dart';
import 'enums.dart';

enum JobStatus {
  draft('Draft'),
  pending('Awaiting approval'),
  published('Live'),
  closed('Closed'),

  /// Sent back by an admin; the employer can edit and resubmit.
  declined('Changes needed'),

  /// Refused by an admin; final.
  rejected('Rejected');

  const JobStatus(this.label);
  final String label;
}

class Job {
  const Job({
    required this.id,
    required this.title,
    required this.companyId,
    required this.location,
    required this.employmentType,
    required this.workMode,
    required this.industry,
    required this.experienceLevel,
    required this.salaryMin,
    required this.salaryMax,
    required this.postedAt,
    required this.deadline,
    required this.about,
    required this.description,
    required this.responsibilities,
    required this.requirements,
    required this.preferred,
    required this.skills,
    required this.benefits,
    this.currency = 'SLE',
    this.salaryPeriod = 'month',
    this.applicants = 0,
    this.featured = false,
    this.company,
    this.status = JobStatus.published,
    this.views = 0,
    this.reviewNote = '',
    this.documentsRequested = false,
    this.documentsNote = '',
    this.applyUrl = '',
    this.applyClicks = 0,
    this.featureRequestedAt,
    this.screening = const [],
  });

  final String id;
  final String title;
  final String companyId;
  final String location;
  final EmploymentType employmentType;
  final WorkMode workMode;
  final Industry industry;
  final ExperienceLevel experienceLevel;
  final int? salaryMin;
  final int? salaryMax;
  final String currency;
  final String salaryPeriod;
  final DateTime postedAt;
  final DateTime deadline;
  final String about;
  final String description;
  final List<String> responsibilities;
  final List<String> requirements;
  final List<String> preferred;
  final List<String> skills;
  final List<String> benefits;
  final int applicants;
  final bool featured;
  final JobStatus status;
  final int views;

  /// The admin's reason when a job is declined or rejected.
  final String reviewNote;

  /// The employer asks applicants for supporting documents (up to 5 PDFs, optional).
  final bool documentsRequested;

  /// Which documents, e.g. "Certificates and a copy of your ID".
  final String documentsNote;

  /// When set, candidates apply on the employer's own website instead of in the app.
  final String applyUrl;
  bool get appliesExternally => applyUrl.isNotEmpty;

  /// Taps on "Apply on website" (jobs with an external link).
  final int applyClicks;

  /// When the employer asked for this job to be featured (null if never).
  final DateTime? featureRequestedAt;
  bool get featureRequested => featureRequestedAt != null && !featured;

  /// Yes/no questions candidates answer when applying (up to 5).
  final List<ScreeningQuestion> screening;

  /// The website name shown to candidates before they leave the app, e.g. careers.example.org.
  String get applyHost => Uri.tryParse(applyUrl)?.host ?? applyUrl;

  /// Cleans an employer-entered link: adds https:// if missing. Null if it isn't a web address.
  static String? normalizeApplyUrl(String input) {
    var t = input.trim();
    if (t.isEmpty) return null;
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(t)) t = 'https://$t';
    final u = Uri.tryParse(t);
    if (u == null || !u.hasAuthority || !u.host.contains('.') || u.host.contains(' ')) return null;
    return u.toString();
  }

  /// Populated by repositories so the UI never has to join data itself.
  final Company? company;

  String get companyName => company?.name ?? '';
  bool get isClosed => deadline.isBefore(DateTime.now());
  int get daysToDeadline => deadline.difference(DateTime.now()).inDays;

  Job withCompany(Company? c) => Job(
        id: id,
        title: title,
        companyId: companyId,
        location: location,
        employmentType: employmentType,
        workMode: workMode,
        industry: industry,
        experienceLevel: experienceLevel,
        salaryMin: salaryMin,
        salaryMax: salaryMax,
        currency: currency,
        salaryPeriod: salaryPeriod,
        postedAt: postedAt,
        deadline: deadline,
        about: about,
        description: description,
        responsibilities: responsibilities,
        requirements: requirements,
        preferred: preferred,
        skills: skills,
        benefits: benefits,
        applicants: applicants,
        featured: featured,
        company: c,
        status: status,
        views: views,
        reviewNote: reviewNote,
        documentsRequested: documentsRequested,
        documentsNote: documentsNote,
        applyUrl: applyUrl,
        applyClicks: applyClicks,
        featureRequestedAt: featureRequestedAt,
        screening: screening,
      );

  factory Job.fromJson(Map<String, dynamic> j) => Job(
        id: j['id'] as String,
        title: j['title'] as String,
        companyId: j['company_id'] as String,
        location: j['location'] as String? ?? '',
        employmentType: enumByName(EmploymentType.values, j['employment_type'], EmploymentType.fullTime),
        workMode: enumByName(WorkMode.values, j['work_mode'], WorkMode.onsite),
        industry: enumByName(Industry.values, j['industry'], Industry.technology),
        experienceLevel: enumByName(ExperienceLevel.values, j['experience_level'], ExperienceLevel.mid),
        salaryMin: (j['salary_min'] as num?)?.toInt(),
        salaryMax: (j['salary_max'] as num?)?.toInt(),
        currency: j['currency'] as String? ?? 'SLE',
        salaryPeriod: j['salary_period'] as String? ?? 'month',
        postedAt: DateTime.parse(j['posted_at'] as String),
        deadline: DateTime.parse(j['deadline'] as String),
        about: j['about'] as String? ?? '',
        description: j['description'] as String? ?? '',
        responsibilities: _list(j['responsibilities']),
        requirements: _list(j['requirements']),
        preferred: _list(j['preferred']),
        skills: _list(j['skills']),
        benefits: _list(j['benefits']),
        applicants: (j['applicants'] as num?)?.toInt() ?? 0,
        featured: j['featured'] as bool? ?? false,
        status: enumByName(JobStatus.values, j['status'], JobStatus.published),
        views: (j['views'] as num?)?.toInt() ?? 0,
        reviewNote: j['review_note'] as String? ?? '',
        documentsRequested: j['documents_requested'] as bool? ?? false,
        documentsNote: j['documents_note'] as String? ?? '',
        applyUrl: j['apply_url'] as String? ?? '',
        applyClicks: (j['apply_clicks'] as num?)?.toInt() ?? 0,
        featureRequestedAt: j['feature_requested_at'] == null ? null : DateTime.tryParse('${j['feature_requested_at']}'),
        screening: [
          for (final q in (j['screening'] as List? ?? const [])) ScreeningQuestion.fromJson(Map<String, dynamic>.from(q as Map))
        ],
        company: j['company'] is Map<String, dynamic> ? Company.fromJson(j['company'] as Map<String, dynamic>) : null,
      );

  Map<String, dynamic> toJson({bool includeCompany = true}) => {
        'id': id,
        'title': title,
        'company_id': companyId,
        'location': location,
        'employment_type': employmentType.name,
        'work_mode': workMode.name,
        'industry': industry.name,
        'experience_level': experienceLevel.name,
        'salary_min': salaryMin,
        'salary_max': salaryMax,
        'currency': currency,
        'salary_period': salaryPeriod,
        'posted_at': postedAt.toIso8601String(),
        'deadline': deadline.toIso8601String(),
        'about': about,
        'description': description,
        'responsibilities': responsibilities,
        'requirements': requirements,
        'preferred': preferred,
        'skills': skills,
        'benefits': benefits,
        'applicants': applicants,
        'featured': featured,
        'status': status.name,
        'views': views,
        'review_note': reviewNote,
        'documents_requested': documentsRequested,
        'documents_note': documentsNote,
        'apply_url': applyUrl,
        'apply_clicks': applyClicks,
        'feature_requested_at': featureRequestedAt?.toIso8601String(),
        'screening': screening.map((q) => q.toJson()).toList(),
        if (includeCompany && company != null) 'company': company!.toJson(),
      };
}

List<String> _list(Object? v) => v is List ? v.map((e) => e.toString()).toList() : const [];

/// A yes/no question an employer asks applicants, e.g. "Do you have a driving licence?".
class ScreeningQuestion {
  const ScreeningQuestion({required this.id, required this.text, this.wanted});

  static const maxPerJob = 5;

  final String id;
  final String text;

  /// The answer the employer is looking for; null if either answer is fine.
  final bool? wanted;

  factory ScreeningQuestion.fromJson(Map<String, dynamic> j) =>
      ScreeningQuestion(id: j['id'] as String? ?? '', text: j['text'] as String? ?? '', wanted: j['wanted'] as bool?);

  Map<String, dynamic> toJson() => {'id': id, 'text': text, 'wanted': wanted};
}
