import 'documents.dart';
import 'enums.dart';
import 'notification.dart';

class Experience {
  const Experience({
    required this.title,
    required this.company,
    required this.location,
    required this.start,
    this.end,
    this.description = '',
  });
  final String title;
  final String company;
  final String location;
  final DateTime start;
  final DateTime? end;
  final String description;
  bool get current => end == null;

  factory Experience.fromJson(Map<String, dynamic> j) => Experience(
        title: j['title'] as String? ?? '',
        company: j['company'] as String? ?? '',
        location: j['location'] as String? ?? '',
        start: DateTime.parse(j['start'] as String),
        end: j['end'] == null ? null : DateTime.parse(j['end'] as String),
        description: j['description'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'company': company,
        'location': location,
        'start': start.toIso8601String(),
        'end': end?.toIso8601String(),
        'description': description,
      };
}

class Education {
  const Education({required this.school, required this.degree, required this.field, required this.startYear, this.endYear});
  final String school;
  final String degree;
  final String field;
  final int startYear;
  final int? endYear;

  factory Education.fromJson(Map<String, dynamic> j) => Education(
        school: j['school'] as String? ?? '',
        degree: j['degree'] as String? ?? '',
        field: j['field'] as String? ?? '',
        startYear: (j['start_year'] as num?)?.toInt() ?? 0,
        endYear: (j['end_year'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() =>
      {'school': school, 'degree': degree, 'field': field, 'start_year': startYear, 'end_year': endYear};
}

class Certification {
  const Certification({required this.name, required this.issuer, required this.year});
  final String name;
  final String issuer;
  final int year;

  factory Certification.fromJson(Map<String, dynamic> j) => Certification(
        name: j['name'] as String? ?? '',
        issuer: j['issuer'] as String? ?? '',
        year: (j['year'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {'name': name, 'issuer': issuer, 'year': year};
}

class LanguageSkill {
  const LanguageSkill({required this.name, required this.level});
  final String name;
  final String level;

  factory LanguageSkill.fromJson(Map<String, dynamic> j) =>
      LanguageSkill(name: j['name'] as String? ?? '', level: j['level'] as String? ?? '');

  Map<String, dynamic> toJson() => {'name': name, 'level': level};
}

class JobPreferences {
  const JobPreferences({
    this.titles = const [],
    this.industries = const {},
    this.locations = const {},
    this.workModes = const {},
    this.employmentTypes = const {},
    this.salaryExpectation,
  });

  final List<String> titles;
  final Set<Industry> industries;
  final Set<String> locations;
  final Set<WorkMode> workModes;
  final Set<EmploymentType> employmentTypes;

  /// Monthly expectation in SLE.
  final int? salaryExpectation;

  bool get isEmpty => titles.isEmpty && industries.isEmpty && locations.isEmpty;

  factory JobPreferences.fromJson(Map<String, dynamic> j) => JobPreferences(
        titles: (j['titles'] as List? ?? const []).cast<String>(),
        industries: {for (final n in (j['industries'] as List? ?? const [])) enumByName(Industry.values, n, Industry.technology)},
        locations: {...(j['locations'] as List? ?? const []).cast<String>()},
        workModes: {for (final n in (j['work_modes'] as List? ?? const [])) enumByName(WorkMode.values, n, WorkMode.onsite)},
        employmentTypes: {
          for (final n in (j['employment_types'] as List? ?? const []))
            enumByName(EmploymentType.values, n, EmploymentType.fullTime)
        },
        salaryExpectation: (j['salary_expectation'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'titles': titles,
        'industries': industries.map((e) => e.name).toList(),
        'locations': locations.toList(),
        'work_modes': workModes.map((e) => e.name).toList(),
        'employment_types': employmentTypes.map((e) => e.name).toList(),
        'salary_expectation': salaryExpectation,
      };
}

class AppUser {
  const AppUser({
    required this.id,
    required this.fullName,
    required this.email,
    this.phone = '',
    this.photoBase64,
    this.headline = '',
    this.location = '',
    this.about = '',
    this.experience = const [],
    this.education = const [],
    this.skills = const [],
    this.certifications = const [],
    this.languages = const [],
    this.resume,
    this.portfolioUrl = '',
    this.linkedinUrl = '',
    this.preferences = const JobPreferences(),
    this.notificationPreferences = const NotificationPreferences(),
  });

  final String id;
  final String fullName;
  final String email;
  final String phone;
  final String? photoBase64;
  final String headline;
  final String location;
  final String about;
  final List<Experience> experience;
  final List<Education> education;
  final List<String> skills;
  final List<Certification> certifications;
  final List<LanguageSkill> languages;
  final Resume? resume;
  final String portfolioUrl;
  final String linkedinUrl;
  final JobPreferences preferences;
  final NotificationPreferences notificationPreferences;

  String get firstName => fullName.split(' ').first;
  String get initials {
    final p = fullName.trim().split(RegExp(r'\s+'));
    return p.length > 1 ? '${p.first[0]}${p.last[0]}'.toUpperCase() : fullName.substring(0, 1).toUpperCase();
  }

  /// Weighted checklist used for the profile-strength meter.
  List<({String label, bool done, int weight})> get completionChecklist => [
        (label: 'Profile photo', done: photoBase64 != null, weight: 10),
        (label: 'Headline', done: headline.isNotEmpty, weight: 10),
        (label: 'Location', done: location.isNotEmpty, weight: 5),
        (label: 'Phone number', done: phone.isNotEmpty, weight: 5),
        (label: 'About you', done: about.length >= 40, weight: 10),
        (label: 'Work experience', done: experience.isNotEmpty, weight: 15),
        (label: 'Education', done: education.isNotEmpty, weight: 10),
        (label: 'At least 5 skills', done: skills.length >= 5, weight: 10),
        (label: 'CV uploaded', done: resume != null, weight: 15),
        (label: 'Languages', done: languages.isNotEmpty, weight: 5),
        (label: 'Job preferences', done: !preferences.isEmpty, weight: 5),
      ];

  int get completion {
    final items = completionChecklist;
    final total = items.fold<int>(0, (s, i) => s + i.weight);
    final done = items.where((i) => i.done).fold<int>(0, (s, i) => s + i.weight);
    return (done * 100 / total).round();
  }

  AppUser copyWith({
    String? fullName,
    String? phone,
    String? Function()? photoBase64,
    String? headline,
    String? location,
    String? about,
    List<Experience>? experience,
    List<Education>? education,
    List<String>? skills,
    List<Certification>? certifications,
    List<LanguageSkill>? languages,
    Resume? Function()? resume,
    String? portfolioUrl,
    String? linkedinUrl,
    JobPreferences? preferences,
    NotificationPreferences? notificationPreferences,
  }) =>
      AppUser(
        id: id,
        email: email,
        fullName: fullName ?? this.fullName,
        phone: phone ?? this.phone,
        photoBase64: photoBase64 != null ? photoBase64() : this.photoBase64,
        headline: headline ?? this.headline,
        location: location ?? this.location,
        about: about ?? this.about,
        experience: experience ?? this.experience,
        education: education ?? this.education,
        skills: skills ?? this.skills,
        certifications: certifications ?? this.certifications,
        languages: languages ?? this.languages,
        resume: resume != null ? resume() : this.resume,
        portfolioUrl: portfolioUrl ?? this.portfolioUrl,
        linkedinUrl: linkedinUrl ?? this.linkedinUrl,
        preferences: preferences ?? this.preferences,
        notificationPreferences: notificationPreferences ?? this.notificationPreferences,
      );

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        fullName: j['full_name'] as String? ?? '',
        email: j['email'] as String? ?? '',
        phone: j['phone'] as String? ?? '',
        photoBase64: j['photo_base64'] as String?,
        headline: j['headline'] as String? ?? '',
        location: j['location'] as String? ?? '',
        about: j['about'] as String? ?? '',
        experience: [for (final e in (j['experience'] as List? ?? const [])) Experience.fromJson(Map<String, dynamic>.from(e as Map))],
        education: [for (final e in (j['education'] as List? ?? const [])) Education.fromJson(Map<String, dynamic>.from(e as Map))],
        skills: (j['skills'] as List? ?? const []).cast<String>(),
        certifications: [
          for (final e in (j['certifications'] as List? ?? const [])) Certification.fromJson(Map<String, dynamic>.from(e as Map))
        ],
        languages: [for (final e in (j['languages'] as List? ?? const [])) LanguageSkill.fromJson(Map<String, dynamic>.from(e as Map))],
        resume: j['resume'] == null ? null : Resume.fromJson(Map<String, dynamic>.from(j['resume'] as Map)),
        portfolioUrl: j['portfolio_url'] as String? ?? '',
        linkedinUrl: j['linkedin_url'] as String? ?? '',
        preferences: JobPreferences.fromJson(Map<String, dynamic>.from(j['preferences'] as Map? ?? const {})),
        notificationPreferences:
            NotificationPreferences.fromJson(Map<String, dynamic>.from(j['notification_preferences'] as Map? ?? const {})),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'email': email,
        'phone': phone,
        'photo_base64': photoBase64,
        'headline': headline,
        'location': location,
        'about': about,
        'experience': experience.map((e) => e.toJson()).toList(),
        'education': education.map((e) => e.toJson()).toList(),
        'skills': skills,
        'certifications': certifications.map((e) => e.toJson()).toList(),
        'languages': languages.map((e) => e.toJson()).toList(),
        'resume': resume?.toJson(),
        'portfolio_url': portfolioUrl,
        'linkedin_url': linkedinUrl,
        'preferences': preferences.toJson(),
        'notification_preferences': notificationPreferences.toJson(),
      };
}
