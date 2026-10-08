import 'package:flutter_test/flutter_test.dart';
import 'package:vocation_sl/services/cv_parser.dart';

const _classic = '''
FATMATA KAMARA
Accounts Assistant
12 Wilkinson Road, Freetown, Sierra Leone | +232 76 123 456 | fatmata.kamara@gmail.com
linkedin.com/in/fatmatakamara

PROFESSIONAL SUMMARY
Detail-oriented accounts assistant with four years of experience in bookkeeping,
payroll and monthly reconciliations for wholesale businesses.

WORK EXPERIENCE
Accounts Assistant – Lumley Trading Co.
February 2022 – Present
• Process supplier invoices and payments
• Prepare monthly bank reconciliations

Accounts Clerk
Bo Wholesale Ltd, Bo
Jan 2020 - Jan 2022
• Recorded daily sales and expenses

EDUCATION
Fourah Bay College, University of Sierra Leone
BSc in Accounting, 2016 – 2020
St. Joseph's Secondary School
WASSCE, 2015

SKILLS
Bookkeeping, QuickBooks, Payroll, Microsoft Excel, Reconciliations

LANGUAGES
English (Fluent), Krio (Native), Mende (Intermediate)

CERTIFICATIONS
Certified Bookkeeper – ACCA, 2021

REFERENCES
Available on request
''';

const _compact = '''
Mohamed Bangura
Software Developer
Kenema
Phone: 077 555 123  Email: m.bangura@example.com

Profile:
I build mobile and web apps with Flutter and Firebase.

Employment History
Junior Developer at Salone Digital Labs (03/2023 - present)
- Built Flutter screens and REST integrations
Intern, Kenema City Council
06/2022 - 12/2022
- Supported the IT helpdesk

Education
Njala University
Bachelor of Science in Computer Science 2018 - 2022

Key Skills
Flutter; Dart; Firebase; Git; REST APIs
''';

void main() {
  const parser = CvParser();

  test('classic CV: contacts, summary and sections', () {
    final cv = parser.parse(_classic);
    expect(cv.headline, 'Accounts Assistant');
    expect(cv.phone, '+232 76 123 456');
    expect(cv.location, 'Freetown');
    expect(cv.linkedinUrl, 'https://linkedin.com/in/fatmatakamara');
    expect(cv.about, startsWith('Detail-oriented accounts assistant'));

    expect(cv.experience.length, 2);
    final current = cv.experience.first;
    expect(current.title, 'Accounts Assistant');
    expect(current.company, 'Lumley Trading Co.');
    expect(current.start, DateTime(2022, 2));
    expect(current.current, isTrue);
    expect(current.description, contains('supplier invoices'));
    final previous = cv.experience.last;
    expect(previous.title, 'Accounts Clerk');
    expect(previous.company, startsWith('Bo Wholesale'));
    expect(previous.end, DateTime(2022, 1));

    expect(cv.education.first.school, contains('Fourah Bay College'));
    expect(cv.education.first.degree, 'BSc');
    expect(cv.education.first.field, 'Accounting');
    expect(cv.education.first.startYear, 2016);
    expect(cv.education.first.endYear, 2020);

    expect(cv.skills, containsAll(['Bookkeeping', 'QuickBooks', 'Microsoft Excel']));
    expect({for (final l in cv.languages) l.name: l.level}, {'English': 'Fluent', 'Krio': 'Native', 'Mende': 'Professional'});
    expect(cv.certifications.single.name, 'Certified Bookkeeper');
    expect(cv.certifications.single.issuer, 'ACCA');
    expect(cv.certifications.single.year, 2021);
  });

  test('compact CV: "Title at Company (dates)" and numeric dates', () {
    final cv = parser.parse(_compact);
    expect(cv.headline, 'Software Developer');
    expect(cv.phone, '077 555 123');
    expect(cv.location, 'Kenema');
    expect(cv.about, contains('Flutter and Firebase'));
    expect(cv.experience.first.title, 'Junior Developer');
    expect(cv.experience.first.company, 'Salone Digital Labs');
    expect(cv.experience.first.start, DateTime(2023, 3));
    expect(cv.experience.first.current, isTrue);
    expect(cv.experience.last.title, 'Intern');
    expect(cv.experience.last.company, 'Kenema City Council');
    expect(cv.experience.last.end, DateTime(2022, 12));
    expect(cv.education.single.school, 'Njala University');
    expect(cv.education.single.field, 'Computer Science');
    expect(cv.skills, ['Flutter', 'Dart', 'Firebase', 'Git', 'REST APIs']);
  });

  test('text with no recognisable sections gives an empty result', () {
    expect(parser.parse('').isEmpty, isTrue);
    expect(parser.parse('Hello\nThis is not a CV').experience, isEmpty);
  });
}
