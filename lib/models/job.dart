import 'company.dart';
import 'enums.dart';

enum JobStatus {
  draft('Draft'),
  pending('Awaiting approval'),
  published('Live'),
  closed('Closed');

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
        if (includeCompany && company != null) 'company': company!.toJson(),
      };
}

List<String> _list(Object? v) => v is List ? v.map((e) => e.toString()).toList() : const [];
