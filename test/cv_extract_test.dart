import 'package:flutter_test/flutter_test.dart';
import 'package:vocation_sl/models/models.dart';

void main() {
  final found = CvExtract.fromJson({
    'headline': 'Accounts Assistant',
    'phone': '+232 76 123 456',
    'location': 'Bo Town, Southern Province, Sierra Leone',
    'about': 'Bookkeeper with four years of experience.',
    'experience': [
      {'title': 'Accounts Assistant', 'company': 'Lumley Trading', 'start': '2022-02', 'current': true},
      {'title': 'Accounts Clerk', 'company': 'Bo Wholesale', 'start': '2020', 'end': '2022-01'},
      {'title': '', 'company': ''},
    ],
    'education': [
      {'school': 'Fourah Bay College', 'degree': 'BSc', 'field': 'Accounting', 'start_year': 2016, 'end_year': '2020'},
    ],
    'skills': ['Excel', 'Payroll', 'Excel', ' '],
    'languages': [
      {'name': 'Krio'},
    ],
    'certifications': [
      {'name': 'Certified Bookkeeper', 'year': 2021},
    ],
  });

  test('reads the fields the CV contains and drops empty entries', () {
    expect(found.location, 'Bo', reason: 'matched to a known district or town');
    expect(found.experience.length, 2);
    expect(found.experience.first.current, isTrue);
    expect(found.experience.last.start, DateTime(2020));
    expect(found.experience.last.end, DateTime(2022, 1));
    expect(found.education.single.endYear, 2020);
    expect(found.skills, ['Excel', 'Payroll']);
    expect(found.languages.single.level, 'Fluent');
  });

  test('adds only chosen sections and never overwrites what the user filled in', () {
    final user = AppUser(
      id: 'u',
      fullName: 'Fatmata Kamara',
      email: 'f@example.com',
      headline: 'My own headline',
      skills: const ['excel'],
      experience: [Experience(title: 'Accounts Clerk', company: 'Bo Wholesale', location: 'Bo', start: DateTime(2020))],
    );
    final updated = found.applyTo(user, {CvSection.basics, CvSection.experience, CvSection.skills});
    expect(updated.headline, 'My own headline');
    expect(updated.phone, '+232 76 123 456');
    expect(updated.location, 'Bo');
    expect(updated.experience.length, 2, reason: 'the existing Bo Wholesale job is not duplicated');
    expect(updated.experience.first.company, 'Lumley Trading', reason: 'newest first');
    expect(updated.skills, ['excel', 'Payroll']);
    expect(updated.education, isEmpty, reason: 'education was not chosen');
  });

  test('an empty reading is reported as empty', () {
    expect(CvExtract.fromJson(const {}).isEmpty, isTrue);
    expect(CvExtract.matchLocation('Somewhere else'), '');
  });
}
