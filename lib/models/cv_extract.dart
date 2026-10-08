import 'enums.dart';
import 'user.dart';

/// Profile details read from a CV. Every field may be empty: the reader only
/// returns what the CV actually says.
class CvExtract {
  const CvExtract({
    this.fullName = '',
    this.headline = '',
    this.phone = '',
    this.location = '',
    this.about = '',
    this.experience = const [],
    this.education = const [],
    this.skills = const [],
    this.languages = const [],
    this.certifications = const [],
    this.linkedinUrl = '',
    this.portfolioUrl = '',
  });

  final String fullName;
  final String headline;
  final String phone;

  /// A district or town from [sierraLeoneLocations], or empty.
  final String location;
  final String about;
  final List<Experience> experience;
  final List<Education> education;
  final List<String> skills;
  final List<LanguageSkill> languages;
  final List<Certification> certifications;
  final String linkedinUrl;
  final String portfolioUrl;

  bool get isEmpty =>
      headline.isEmpty &&
      phone.isEmpty &&
      location.isEmpty &&
      about.isEmpty &&
      experience.isEmpty &&
      education.isEmpty &&
      skills.isEmpty &&
      languages.isEmpty &&
      certifications.isEmpty;

  static String _s(Object? v) => v is String ? v.trim() : '';
  static int? _year(Object? v) {
    if (v is num) return v.toInt();
    final m = RegExp(r'(19|20)\d{2}').firstMatch('${v ?? ''}');
    return m == null ? null : int.parse(m.group(0)!);
  }

  /// "2021-03", "2021" or "March 2021" → first day of that month; null if unknown.
  static DateTime? _date(Object? v) {
    final s = _s(v);
    if (s.isEmpty) return null;
    final ym = RegExp(r'((?:19|20)\d{2})(?:[-/.](\d{1,2}))?').firstMatch(s);
    if (ym == null) return null;
    final month = int.tryParse(ym.group(2) ?? '') ?? 1;
    return DateTime(int.parse(ym.group(1)!), month.clamp(1, 12));
  }

  /// Matches free text like "Freetown, Sierra Leone" or "Kenema District" to a known location.
  static String matchLocation(String raw) {
    final t = raw.toLowerCase();
    if (t.isEmpty) return '';
    for (final l in sierraLeoneLocations) {
      if (t.contains(l.toLowerCase())) return l;
    }
    return '';
  }

  factory CvExtract.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> maps(String k) => [for (final e in (j[k] as List? ?? const [])) if (e is Map) Map<String, dynamic>.from(e)];
    final now = DateTime.now();
    return CvExtract(
      fullName: _s(j['full_name']),
      headline: _s(j['headline']),
      phone: _s(j['phone']),
      location: matchLocation(_s(j['location'])),
      about: _s(j['about']),
      experience: [
        for (final e in maps('experience'))
          if (_s(e['title']).isNotEmpty || _s(e['company']).isNotEmpty)
            Experience(
              title: _s(e['title']),
              company: _s(e['company']),
              location: _s(e['location']),
              start: _date(e['start']) ?? DateTime(now.year),
              // A current role has no end date.
              end: e['current'] == true ? null : (_date(e['end']) ?? _date(e['start']) ?? DateTime(now.year)),
              description: _s(e['description']),
            ),
      ],
      education: [
        for (final e in maps('education'))
          if (_s(e['school']).isNotEmpty)
            Education(
              school: _s(e['school']),
              degree: _s(e['degree']),
              field: _s(e['field']),
              startYear: _year(e['start_year']) ?? _year(e['end_year']) ?? now.year,
              endYear: _year(e['end_year']),
            ),
      ],
      skills: <String>{
        for (final s in (j['skills'] as List? ?? const []))
          if (s is String && s.trim().isNotEmpty) s.trim(),
      }.take(30).toList(),
      languages: [
        for (final e in maps('languages'))
          if (_s(e['name']).isNotEmpty) LanguageSkill(name: _s(e['name']), level: _s(e['level']).isEmpty ? 'Fluent' : _s(e['level'])),
      ],
      certifications: [
        for (final e in maps('certifications'))
          if (_s(e['name']).isNotEmpty) Certification(name: _s(e['name']), issuer: _s(e['issuer']), year: _year(e['year']) ?? now.year),
      ],
      linkedinUrl: _s(j['linkedin_url']),
      portfolioUrl: _s(j['portfolio_url']),
    );
  }

  /// Adds the chosen parts to [user]. Text fields are only filled when empty;
  /// lists are added to, skipping entries the profile already has.
  AppUser applyTo(AppUser user, Set<CvSection> sections) {
    bool has(CvSection s) => sections.contains(s);
    String fill(String current, String found) => current.trim().isEmpty ? found : current;
    String key(String a, String b) => '${a.trim().toLowerCase()}|${b.trim().toLowerCase()}';

    final expKeys = {for (final e in user.experience) key(e.title, e.company)};
    final eduKeys = {for (final e in user.education) key(e.school, e.degree)};
    final skillKeys = {for (final s in user.skills) s.toLowerCase()};
    final langKeys = {for (final l in user.languages) l.name.toLowerCase()};
    final certKeys = {for (final c in user.certifications) c.name.toLowerCase()};

    return user.copyWith(
      headline: has(CvSection.basics) ? fill(user.headline, headline) : null,
      phone: has(CvSection.basics) ? fill(user.phone, phone) : null,
      location: has(CvSection.basics) ? fill(user.location, location) : null,
      about: has(CvSection.basics) ? fill(user.about, about) : null,
      linkedinUrl: has(CvSection.basics) ? fill(user.linkedinUrl, linkedinUrl) : null,
      portfolioUrl: has(CvSection.basics) ? fill(user.portfolioUrl, portfolioUrl) : null,
      experience: has(CvSection.experience)
          ? ([...user.experience, ...experience.where((e) => !expKeys.contains(key(e.title, e.company)))]
            ..sort((a, b) => b.start.compareTo(a.start)))
          : null,
      education: has(CvSection.education) ? [...user.education, ...education.where((e) => !eduKeys.contains(key(e.school, e.degree)))] : null,
      skills: has(CvSection.skills) ? [...user.skills, ...skills.where((s) => !skillKeys.contains(s.toLowerCase()))] : null,
      languages: has(CvSection.languages) ? [...user.languages, ...languages.where((l) => !langKeys.contains(l.name.toLowerCase()))] : null,
      certifications:
          has(CvSection.certifications) ? [...user.certifications, ...certifications.where((c) => !certKeys.contains(c.name.toLowerCase()))] : null,
    );
  }
}

enum CvSection {
  basics('Headline, about, phone and location'),
  experience('Work experience'),
  education('Education'),
  skills('Skills'),
  languages('Languages'),
  certifications('Certifications');

  const CvSection(this.label);
  final String label;
}
