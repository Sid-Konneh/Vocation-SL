import 'enums.dart';

/// Job details copied word for word from the text of a PDF job advert.
/// No AI and no online service: only clearly labelled details are taken
/// ("Position:", "Location:", "Closing date: 23 November 2026", a
/// "Responsibilities" heading, an email to send applications to...).
/// Anything the advert doesn't say clearly is left out.
class AdvertExtract {
  const AdvertExtract({
    this.title,
    this.location,
    this.employmentType,
    this.deadline,
    this.applyEmail,
    this.applyUrl,
    this.responsibilities = const [],
    this.requirements = const [],
    this.description = '',
  });

  final String? title;
  final String? location;
  final EmploymentType? employmentType;
  final DateTime? deadline;
  final String? applyEmail;
  final String? applyUrl;
  final List<String> responsibilities;
  final List<String> requirements;

  /// The advert's whole text, as written.
  final String description;

  bool get isEmpty =>
      title == null &&
      location == null &&
      employmentType == null &&
      deadline == null &&
      applyEmail == null &&
      applyUrl == null &&
      responsibilities.isEmpty &&
      requirements.isEmpty &&
      description.isEmpty;

  static const _months = {
    'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
    'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
  };
  static const _monthRe = r'(jan(?:uary)?|feb(?:ruary)?|mar(?:ch)?|apr(?:il)?|may|june?|july?|aug(?:ust)?|sep(?:t(?:ember)?)?|oct(?:ober)?|nov(?:ember)?|dec(?:ember)?)';

  static final _respHeading = RegExp(
      r'^(key |main |major |specific )?(duties|responsibilities|duties (and|&) responsibilities|roles? (and|&) responsibilities|job (duties|responsibilities)|tasks)\b[^a-z]*$',
      caseSensitive: false);
  static final _reqHeading = RegExp(
      r'^(minimum |required |essential |key )?(requirements|qualifications?|qualifications? (and|&) experience|eligibility( criteria)?|experience (and|&) qualifications?|education (and|&) experience|skills (and|&) (competencies|experience)|competencies|person specification|who (we are looking for|can apply))\b[^a-z]*$',
      caseSensitive: false);
  // Other headings that end a section.
  static final _otherHeading = RegExp(
      r'^(how to apply|application (procedure|process|instructions)|to apply|closing date|deadline|about (us|the (organi[sz]ation|company|role|job))|background|benefits|remuneration|salary|location|duty station|reports? to|purpose of the (job|position|role)|job (summary|purpose|description)|position summary|overview|note|n\.?b\.?|desirable|preferred|other (information|requirements))\b.*$',
      caseSensitive: false);

  static AdvertExtract parse(String raw, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final text = raw.replaceAll('\r', '\n').replaceAll(' ', ' ');
    final lines = [
      for (final l in text.split('\n')) l.replaceAll(RegExp(r'[ \t]+'), ' ').trim(),
    ];
    final description = lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();

    return AdvertExtract(
      title: _title(lines),
      location: _location(lines, text),
      employmentType: _type(lines, text),
      deadline: _deadline(lines, today),
      applyEmail: _email(lines),
      applyUrl: _url(lines),
      responsibilities: _section(lines, _respHeading),
      requirements: _section(lines, _reqHeading),
      description: description,
    );
  }

  /// The value after a label such as "Position:" on the same line.
  static String? _labelled(List<String> lines, String labels) {
    final re = RegExp('^(?:$labels)\\s*[:\\-–—]\\s*(.+)\$', caseSensitive: false);
    for (final l in lines) {
      final m = re.firstMatch(l);
      if (m != null && m.group(1)!.trim().isNotEmpty) return m.group(1)!.trim();
    }
    return null;
  }

  static String? _title(List<String> lines) {
    var t = _labelled(lines, r'job title|position title|title of (?:the )?(?:post|position)|position|post|vacancy|role');
    if (t == null) {
      // "VACANCY ANNOUNCEMENT" (or similar) on its own line, then the job title.
      final heading = RegExp(r'^(job )?(vacanc(y|ies)|opening)( announcement| notice)?\s*:?$|^(we are|is) (recruiting|hiring)( for)?\s*:?$', caseSensitive: false);
      for (var i = 0; i < lines.length - 1 && t == null; i++) {
        if (!heading.hasMatch(lines[i])) continue;
        for (var k = i + 1; k < lines.length && k <= i + 3; k++) {
          if (lines[k].isNotEmpty) {
            t = lines[k];
            break;
          }
        }
      }
    }
    if (t == null) return null;
    t = t.replaceAll(RegExp(r'\s*[-–(]?\s*\d+\s+positions?\)?\s*$', caseSensitive: false), '').trim();
    return t.isEmpty || t.length > 100 ? null : t;
  }

  static final _places = <String, String>{
    for (final p in sierraLeoneLocations) p: p,
    'Western Area': 'Western Area Urban',
    'Koidu Town': 'Koidu',
  };

  static List<String> _placesIn(String s) {
    final found = <String>[];
    // Longest names first, so "Western Area Urban" wins over "Western Area".
    final names = _places.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    var rest = s;
    for (final n in names) {
      final re = RegExp('\\b${RegExp.escape(n)}\\b'); // case-sensitive: "Bo", not "bo"
      if (re.hasMatch(rest)) {
        found.add(_places[n]!);
        rest = rest.replaceAll(re, ' ');
      }
    }
    return found;
  }

  static String? _location(List<String> lines, String text) {
    final v = _labelled(lines, r'location|duty station|work station|job location|place of work|based in|station');
    if (v != null) {
      final p = _placesIn(v);
      if (p.isNotEmpty) return p.first;
    }
    final all = _placesIn(text).toSet();
    return all.length == 1 ? all.first : null;
  }

  static EmploymentType? _typeIn(String s) {
    final l = s.toLowerCase();
    final hits = <EmploymentType>{
      if (RegExp(r'\bintern(ship)?s?\b').hasMatch(l)) EmploymentType.internship,
      if (RegExp(r'\bvolunteer(s|ing)?\b').hasMatch(l)) EmploymentType.volunteer,
      if (RegExp(r'\bpart[- ]time\b').hasMatch(l)) EmploymentType.partTime,
      if (RegExp(r'\btemporary\b').hasMatch(l)) EmploymentType.temporary,
      if (RegExp(r'\b(fixed[- ]term|contract)\b').hasMatch(l)) EmploymentType.contract,
      if (RegExp(r'\b(full[- ]time|permanent)\b').hasMatch(l)) EmploymentType.fullTime,
    };
    return hits.length == 1 ? hits.first : null;
  }

  static EmploymentType? _type(List<String> lines, String text) {
    final v = _labelled(lines, r'contract type|type of contract|employment type|type of employment|job type|contract|duration|employment');
    if (v != null) {
      final t = _typeIn(v);
      if (t != null) return t;
    }
    return _typeIn(text);
  }

  static DateTime? _dateIn(String s) {
    final l = s.toLowerCase();
    DateTime? build(int y, int m, int d) {
      if (y < 100) y += 2000;
      if (m < 1 || m > 12 || d < 1 || d > 31) return null;
      final dt = DateTime(y, m, d);
      return dt.month == m ? dt : null;
    }

    var m = RegExp('\\b(\\d{1,2})(?:st|nd|rd|th)?\\s+(?:of\\s+)?$_monthRe\\.?,?\\s+(\\d{4})\\b').firstMatch(l);
    if (m != null) return build(int.parse(m.group(3)!), _months[m.group(2)!.substring(0, 3)]!, int.parse(m.group(1)!));
    m = RegExp('\\b$_monthRe\\.?\\s+(\\d{1,2})(?:st|nd|rd|th)?,?\\s+(\\d{4})\\b').firstMatch(l);
    if (m != null) return build(int.parse(m.group(3)!), _months[m.group(1)!.substring(0, 3)]!, int.parse(m.group(2)!));
    // Numbers: day first, as written in Sierra Leone (23/11/2026).
    m = RegExp(r'\b(\d{1,2})[/.\-](\d{1,2})[/.\-](\d{4}|\d{2})\b').firstMatch(l);
    if (m != null) return build(int.parse(m.group(3)!), int.parse(m.group(2)!), int.parse(m.group(1)!));
    return null;
  }

  static DateTime? _deadline(List<String> lines, DateTime today) {
    final cue = RegExp(r'deadline|closing date|closes|close of applications|on or before|not later than|no later than|latest by|submission date|applications? (must|should) (be|reach)', caseSensitive: false);
    for (var i = 0; i < lines.length; i++) {
      if (!cue.hasMatch(lines[i])) continue;
      final d = _dateIn(lines[i]) ?? (i + 1 < lines.length ? _dateIn(lines[i + 1]) : null);
      if (d != null && !d.isBefore(DateTime(today.year, today.month, today.day))) return d;
    }
    return null;
  }

  static final _emailRe = RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}');
  static final _applyCue = RegExp(r'appl(y|ication)|send|submit|forward|e-?mail|cv|resume|cover letter', caseSensitive: false);

  static String? _email(List<String> lines) {
    final all = <String>{};
    for (final l in lines) {
      final found = _emailRe.allMatches(l).map((m) => m.group(0)!.replaceAll(RegExp(r'\.$'), '')).toList();
      if (found.isEmpty) continue;
      if (_applyCue.hasMatch(l)) return found.first;
      all.addAll(found);
    }
    return all.length == 1 ? all.first : null;
  }

  static String? _url(List<String> lines) {
    final re = RegExp(r'https?://[^\s<>()]+|www\.[^\s<>()]+', caseSensitive: false);
    for (final l in lines) {
      if (!RegExp(r'appl(y|ication)', caseSensitive: false).hasMatch(l)) continue;
      final m = re.firstMatch(l);
      if (m != null) {
        final u = m.group(0)!.replaceAll(RegExp(r'[.,;]+$'), '');
        return u.toLowerCase().startsWith('http') ? u : 'https://$u';
      }
    }
    return null;
  }

  static final _bullet = RegExp(r'^([\-•*●▪◦‣⁃➢✓✔>]|\(?\d{1,2}[.)]|\(?[a-z][.)]|[ivx]+[.)])\s*');

  /// The lines under a heading, one item per bullet; a line that carries on
  /// the previous bullet (starts in lower case) is joined to it.
  static List<String> _section(List<String> lines, RegExp heading) {
    final start = lines.indexWhere((l) => l.length <= 70 && heading.hasMatch(l.replaceAll(RegExp(r'[:\s]+$'), '')));
    if (start < 0) return const [];
    final items = <String>[];
    for (var i = start + 1; i < lines.length; i++) {
      final l = lines[i];
      if (l.isEmpty) continue;
      final plain = l.replaceAll(RegExp(r'[:\s]+$'), '');
      final isHeading = plain.length <= 70 &&
          (_respHeading.hasMatch(plain) || _reqHeading.hasMatch(plain) || _otherHeading.hasMatch(plain) ||
              (l.endsWith(':') && !_bullet.hasMatch(l) && plain.split(' ').length <= 6));
      if (isHeading && (items.isNotEmpty || i > start + 1)) break;
      if (isHeading) continue;
      final hasBullet = _bullet.hasMatch(l);
      final text = l.replaceFirst(_bullet, '').trim();
      if (text.isEmpty) continue;
      if (!hasBullet && items.isNotEmpty && RegExp(r'^[a-z(]').hasMatch(text)) {
        items[items.length - 1] = '${items.last} $text';
      } else {
        items.add(text);
      }
      if (items.length >= 30) break;
    }
    return items;
  }
}
