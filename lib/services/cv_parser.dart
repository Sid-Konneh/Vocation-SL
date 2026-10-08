import '../models/models.dart';

/// Reads CV text on the device, without any online service, and returns the
/// profile details it can recognise: contact details, summary, experience,
/// education, skills, languages and certifications.
///
/// It looks for the usual CV section headings and date ranges. It never
/// invents anything: whatever it can't recognise is left empty, and the user
/// reviews the result before it is added to their profile.
class CvParser {
  const CvParser();

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, //
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };

  static const _monthPattern = r'(?:jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)';

  /// "Jan 2020", "January 2020", "01/2020", "2020-01" or "2020".
  static final _datePart = '(?:$_monthPattern\\.?\\s+(?:19|20)\\d{2}|\\d{1,2}[/.-](?:19|20)\\d{2}|(?:19|20)\\d{2}[/.-]\\d{1,2}|(?:19|20)\\d{2})';

  static final _dateRange = RegExp(
    '($_datePart)\\s*(?:-|–|—|to|until|till)\\s*($_datePart|present|current|now|date|ongoing)',
    caseSensitive: false,
  );

  static final _email = RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+');
  static final _phone = RegExp(r'(?:\+?232[\s-]?|0)\d{2}[\s-]?\d{3}[\s-]?\d{3}|\+\d[\d\s-]{7,15}\d');
  static final _url = RegExp(r'(?:https?://)?(?:www\.)?[a-z0-9-]+(?:\.[a-z0-9-]+)+(?:/[^\s,;]*)?', caseSensitive: false);
  static final _year = RegExp(r'(?:19|20)\d{2}');

  static const _sections = <String, List<String>>{
    'about': ['summary', 'profile', 'professional summary', 'career summary', 'about me', 'objective', 'career objective', 'personal statement', 'professional profile', 'personal profile'],
    'experience': ['experience', 'work experience', 'professional experience', 'employment history', 'employment', 'work history', 'career history', 'relevant experience', 'working experience'],
    'education': ['education', 'educational background', 'academic background', 'academic qualifications', 'education and training', 'qualifications', 'educational qualifications'],
    'skills': ['skills', 'key skills', 'core skills', 'technical skills', 'core competencies', 'competencies', 'skills and abilities', 'computer skills', 'areas of expertise'],
    'languages': ['languages', 'language skills', 'language'],
    'certifications': ['certifications', 'certificates', 'certification', 'licenses', 'licences', 'training', 'courses', 'professional development', 'trainings attended'],
    'ignore': ['references', 'referees', 'hobbies', 'interests', 'hobbies and interests', 'personal details', 'personal information', 'contact', 'contact details', 'declaration', 'achievements', 'awards', 'volunteering', 'projects'],
  };

  static const _knownLanguages = [
    'English', 'Krio', 'Mende', 'Temne', 'Limba', 'Kono', 'Fula', 'Fulani', 'Sherbro', 'Loko', 'Kissi', 'Susu', 'Yalunka',
    'Kuranko', 'Mandingo', 'Vai', 'French', 'Arabic', 'Spanish', 'Portuguese', 'Chinese', 'German',
  ];

  static const _degreeWords = [
    'phd', 'doctorate', 'master', 'msc', 'm.sc', 'mba', 'ma ', 'bachelor', 'bsc', 'b.sc', 'ba ', 'b.a', 'beng', 'llb', 'hnd', 'ond', 'diploma',
    'certificate', 'wassce', 'bece', 'npse', 'degree', 'associate', 'tc ', 'htc', 'mbbs',
  ];

  static const _schoolWords = ['university', 'college', 'school', 'institute', 'polytechnic', 'academy', 'secondary', 'fourah bay', 'njala', 'ipam', 'comahs', 'limkokwing'];

  CvExtract parse(String raw) {
    final lines = raw
        .replaceAll('\r', '\n')
        .split('\n')
        .map((l) => l.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((l) => l.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const CvExtract();

    // Split into sections by heading lines.
    final sections = <String, List<String>>{'top': []};
    var current = 'top';
    for (final line in lines) {
      final heading = _headingOf(line);
      if (heading != null) {
        current = heading;
        sections.putIfAbsent(current, () => []);
        continue;
      }
      sections.putIfAbsent(current, () => []).add(line);
    }

    final all = lines.join('\n');
    final top = sections['top']!;
    final phone = _phone.firstMatch(all)?.group(0)?.trim() ?? '';
    final urls = _url.allMatches(all).map((m) => m.group(0)!).where((u) => !u.contains('@')).toList();
    final linkedin = urls.firstWhere((u) => u.toLowerCase().contains('linkedin.com/'), orElse: () => '');
    final portfolio = urls.firstWhere(
      (u) => !u.toLowerCase().contains('linkedin') && (u.contains('/') || u.startsWith('www.') || u.startsWith('http')) && !_email.hasMatch(u),
      orElse: () => '',
    );

    var location = '';
    for (final l in top.take(15)) {
      location = CvExtract.matchLocation(l);
      if (location.isNotEmpty) break;
    }
    if (location.isEmpty) location = CvExtract.matchLocation(lines.take(12).join(' '));

    return CvExtract(
      headline: _headline(top),
      phone: phone,
      location: location,
      about: _about(sections['about'] ?? const []),
      linkedinUrl: _withScheme(linkedin),
      portfolioUrl: _withScheme(portfolio),
      experience: _experience(sections['experience'] ?? const []),
      education: _education(sections['education'] ?? const []),
      skills: _skills(sections['skills'] ?? const []),
      languages: _languages([...?sections['languages'], if (sections['languages'] == null) ...lines]),
      certifications: _certifications(sections['certifications'] ?? const []),
    );
  }

  /// The section key if [line] is a heading such as "WORK EXPERIENCE" or "Education:".
  String? _headingOf(String line) {
    final t = line.toLowerCase().replaceAll(RegExp(r'[:\-–—_•*#|]+$'), '').replaceAll(RegExp(r'^[•*#|\-–—\s]+'), '').trim();
    if (t.isEmpty || t.length > 40) return null;
    for (final e in _sections.entries) {
      if (e.value.contains(t)) return e.key;
    }
    return null;
  }

  static String _withScheme(String u) => u.isEmpty || u.startsWith('http') ? u : 'https://$u';

  static bool _isContact(String l) => _email.hasMatch(l) || _phone.hasMatch(l) || l.toLowerCase().contains('linkedin') || l.toLowerCase().startsWith('address');

  /// A short job title near the top, e.g. "Accounts Assistant" under the name.
  String _headline(List<String> top) {
    final candidates = top.take(6).where((l) => !_isContact(l) && l.length >= 4 && l.length <= 60 && !_dateRange.hasMatch(l)).toList();
    if (candidates.length < 2) return '';
    // The first line is normally the person's name; the next short line is the headline.
    final h = candidates[1];
    if (CvExtract.matchLocation(h).isNotEmpty && h.contains(',')) return '';
    if (RegExp(r'^(curriculum vitae|resume|cv)$', caseSensitive: false).hasMatch(h)) return '';
    return h;
  }

  String _about(List<String> lines) {
    final text = lines.where((l) => !_isContact(l)).join(' ').trim();
    return text.length > 600 ? '${text.substring(0, 597).trimRight()}…' : text;
  }

  static DateTime? _parseDate(String s) {
    final t = s.toLowerCase().trim();
    final y = _year.firstMatch(t);
    if (y == null) return null;
    final year = int.parse(y.group(0)!);
    var month = 1;
    final named = RegExp(_monthPattern).firstMatch(t);
    if (named != null) {
      month = _months[named.group(0)!.substring(0, 3)] ?? 1;
    } else {
      final numeric = RegExp(r'^(\d{1,2})[/.-]').firstMatch(t) ?? RegExp(r'[/.-](\d{1,2})$').firstMatch(t);
      if (numeric != null) month = (int.tryParse(numeric.group(1)!) ?? 1).clamp(1, 12);
    }
    return DateTime(year, month);
  }

  static bool _isBullet(String l) => RegExp(r'^[•\-–*▪●◦·]').hasMatch(l);
  static String _unbullet(String l) => l.replaceFirst(RegExp(r'^[•\-–*▪●◦·]\s*'), '');

  /// Splits "Title at Company", "Title - Company", "Title, Company" or "Title | Company".
  static (String, String) _titleCompany(String header, String? nextLine) {
    final h = header.replaceAll(RegExp(r'[(),\s]+$'), '').trim();
    final at = RegExp(r'\s+at\s+', caseSensitive: false);
    if (at.hasMatch(h)) {
      final parts = h.split(at);
      return (parts.first.trim(), parts.skip(1).join(' at ').trim());
    }
    for (final sep in [' | ', ' – ', ' — ', ' - ', ', ']) {
      if (h.contains(sep)) {
        final i = h.indexOf(sep);
        return (h.substring(0, i).trim(), h.substring(i + sep.length).trim());
      }
    }
    if (nextLine != null && nextLine.isNotEmpty && !_isBullet(nextLine) && nextLine.length <= 70 && !_dateRange.hasMatch(nextLine)) {
      return (h, nextLine.trim());
    }
    return (h, '');
  }

  List<Experience> _experience(List<String> lines) {
    final out = <Experience>[];
    for (var i = 0; i < lines.length; i++) {
      final m = _dateRange.firstMatch(lines[i]);
      if (m == null) continue;
      final start = _parseDate(m.group(1)!);
      if (start == null) continue;
      final endText = m.group(2)!.toLowerCase();
      final current = RegExp(r'present|current|now|date|ongoing').hasMatch(endText);
      final end = current ? null : _parseDate(endText);

      // The header is the text on the date line, or the line(s) just above it.
      var header = lines[i].replaceAll(m.group(0)!, '').replaceAll(RegExp(r'^[\s,|:–—-]+|[\s,|:–—-]+$'), '').trim();
      String? next;
      if (header.isEmpty && i > 0 && _dateRange.firstMatch(lines[i - 1]) == null && !_isBullet(lines[i - 1])) {
        header = lines[i - 1];
        if (i > 1 && _dateRange.firstMatch(lines[i - 2]) == null && !_isBullet(lines[i - 2]) && lines[i - 2].length <= 70) {
          // Two lines above the dates: usually title then company.
          final above = lines[i - 2];
          if (!out.any((e) => e.description.contains(above))) {
            next = header;
            header = above;
          }
        }
      } else if (i + 1 < lines.length) {
        next = lines[i + 1];
      }
      final (title, company) = _titleCompany(header, next);
      if (title.isEmpty) continue;

      // Description: bullet or sentence lines until the next dated entry.
      final desc = <String>[];
      for (var j = i + 1; j < lines.length; j++) {
        if (_dateRange.hasMatch(lines[j])) break;
        // The next entry's title (and company) lines come right before its dates.
        if (!_isBullet(lines[j]) && j + 1 < lines.length && _dateRange.hasMatch(lines[j + 1])) break;
        if (!_isBullet(lines[j]) && j + 2 < lines.length && !_isBullet(lines[j + 1]) && _dateRange.hasMatch(lines[j + 2])) break;
        if (next != null && lines[j] == next && j == i + 1 && !_isBullet(lines[j])) continue;
        desc.add(_unbullet(lines[j]));
      }
      final d = desc.join('; ');
      out.add(Experience(
        title: title,
        company: company,
        location: CvExtract.matchLocation('$header ${next ?? ''}'),
        start: start,
        end: end,
        description: d.length > 400 ? '${d.substring(0, 397)}…' : d,
      ));
    }
    out.sort((a, b) => b.start.compareTo(a.start));
    return out;
  }

  List<Education> _education(List<String> lines) {
    final out = <Education>[];
    String? school;
    String? degree;
    final years = <int>[];

    void flush() {
      if (school == null && degree == null) return;
      final d = degree ?? '';
      // "BSc in Accounting" / "Bachelor of Science in Accounting" → degree + field (split at the last " in ").
      final cut = d.toLowerCase().lastIndexOf(' in ');
      final degreeName = cut > 0 ? d.substring(0, cut).trim() : d;
      final field = cut > 0 ? d.substring(cut + 4).trim() : '';
      years.sort();
      out.add(Education(
        school: (school ?? d).replaceAll(_dateRange, '').replaceAll(_year, '').replaceAll(RegExp(r'[\s,|:–—-]+$'), '').trim(),
        degree: school == null ? '' : degreeName.replaceAll(_year, '').replaceAll(RegExp(r'[\s,|:–—-]+$'), '').trim(),
        field: field.replaceAll(_year, '').replaceAll(RegExp(r'[\s,|:()–—-]+$'), '').trim(),
        startYear: years.isEmpty ? DateTime.now().year : years.first,
        endYear: years.length > 1 ? years.last : (years.isEmpty ? null : years.first),
      ));
      school = null;
      degree = null;
      years.clear();
    }

    for (final raw in lines) {
      final l = _unbullet(raw);
      final low = ' ${l.toLowerCase()} ';
      final isSchool = _schoolWords.any(low.contains);
      final isDegree = _degreeWords.any((w) => low.contains(' $w') || low.contains(w));
      final lineYears = _year.allMatches(l).map((m) => int.parse(m.group(0)!)).toList();
      if (isSchool && !isDegree) {
        if (school != null) flush();
        school = l;
      } else if (isDegree) {
        if (degree != null) flush();
        degree = l;
        if (isSchool && school == null) {
          // "BSc Accounting, Fourah Bay College" on one line.
          final parts = l.split(RegExp(r',| - | – | \| | at '));
          final s = parts.where((p) => _schoolWords.any(p.toLowerCase().contains)).firstOrNull;
          if (s != null) {
            school = s.trim();
            degree = parts.where((p) => p != s).join(', ').trim();
          }
        }
      }
      years.addAll(lineYears);
    }
    flush();
    return out.where((e) => e.school.isNotEmpty).toList();
  }

  List<String> _skills(List<String> lines) {
    final items = <String>{};
    for (final raw in lines) {
      for (final part in _unbullet(raw).split(RegExp(r'[,;|•·]|\s{2,}| / '))) {
        var s = part.replaceAll(RegExp(r'^[\s:–—-]+|[\s.:–—-]+$'), '').trim();
        // "Software: Excel, Word" → keep the items after the label.
        if (s.contains(':')) s = s.split(':').last.trim();
        if (s.length >= 2 && s.length <= 40 && s.split(' ').length <= 5) items.add(s);
        if (items.length >= 20) break;
      }
    }
    return items.toList();
  }

  List<LanguageSkill> _languages(List<String> lines) {
    final found = <String, String>{};
    final text = lines.join('\n');
    for (final name in _knownLanguages) {
      final m = RegExp('\\b$name\\b[^\\n,;]{0,30}', caseSensitive: false).firstMatch(text);
      if (m == null) continue;
      final rest = m.group(0)!.toLowerCase();
      final level = rest.contains('native') || rest.contains('mother')
          ? 'Native'
          : rest.contains('fluent') || rest.contains('excellent') || rest.contains('advanced')
              ? 'Fluent'
              : rest.contains('basic') || rest.contains('beginner') || rest.contains('elementary')
                  ? 'Basic'
                  : rest.contains('intermediate') || rest.contains('good') || rest.contains('working') || rest.contains('professional')
                      ? 'Professional'
                      : 'Fluent';
      found[name == 'Fulani' ? 'Fula' : name] = level;
    }
    return [for (final e in found.entries) LanguageSkill(name: e.key, level: e.value)];
  }

  List<Certification> _certifications(List<String> lines) {
    final out = <Certification>[];
    for (final raw in lines) {
      final l = _unbullet(raw);
      if (l.length < 4) continue;
      final y = _year.allMatches(l).map((m) => int.parse(m.group(0)!)).toList();
      var name = l.replaceAll(_dateRange, '').replaceAll(_year, '').replaceAll(RegExp(r'[\s,|:()–—-]+$'), '').trim();
      var issuer = '';
      for (final sep in [' – ', ' — ', ' - ', ' | ', ', ']) {
        if (name.contains(sep)) {
          final i = name.indexOf(sep);
          issuer = name.substring(i + sep.length).trim();
          name = name.substring(0, i).trim();
          break;
        }
      }
      if (name.length < 3) continue;
      out.add(Certification(name: name, issuer: issuer, year: y.isEmpty ? DateTime.now().year : y.last));
      if (out.length >= 15) break;
    }
    return out;
  }
}
