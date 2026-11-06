import 'package:flutter_test/flutter_test.dart';
import 'package:vocation_sl/models/models.dart';

const _advert = '''
AIDS HEALTHCARE FOUNDATION SIERRA LEONE
VACANCY ANNOUNCEMENT
Position: Data Entry Clerk (2 positions)
Location: Ola During Children's Hospital, Freetown
Contract Type: One year fixed-term contract

Key Responsibilities:
• Enter patient data into the electronic system
• Check records for errors and
complete missing information
• Prepare weekly reports

Qualifications and Experience
• Diploma in Computer Science or related field
• At least 1 year of data entry experience

How to Apply
Send your CV and cover letter to globalhr.africa@aidshealth.org
Closing date: 23rd November 2026 at 5:00 pm
''';

void main() {
  final now = DateTime(2026, 11, 6);

  test('advert text: labelled details are copied exactly', () {
    final x = AdvertExtract.parse(_advert, now: now);
    expect(x.title, 'Data Entry Clerk');
    expect(x.location, 'Freetown');
    expect(x.employmentType, EmploymentType.contract);
    expect(x.deadline, DateTime(2026, 11, 23));
    expect(x.applyEmail, 'globalhr.africa@aidshealth.org');
    expect(x.responsibilities, [
      'Enter patient data into the electronic system',
      'Check records for errors and complete missing information',
      'Prepare weekly reports',
    ]);
    expect(x.requirements, ['Diploma in Computer Science or related field', 'At least 1 year of data entry experience']);
    expect(x.description, contains('VACANCY ANNOUNCEMENT'));
  });

  test('advert text: unclear details are left out, past deadlines ignored', () {
    final x = AdvertExtract.parse('We are hiring in Bo and Kenema.\nDeadline: 1 October 2026', now: now);
    expect(x.location, isNull); // two places, no label
    expect(x.deadline, isNull); // already passed
    expect(x.title, isNull);
    expect(AdvertExtract.parse('Closing date: 30/11/2026', now: now).deadline, DateTime(2026, 11, 30));
  });

  test('advert file names keep the employer\'s name', () {
    expect(Job.advertStorageName('AHF Nurse Advert (final).PDF', 'pdf'), 'AHF Nurse Advert (final).pdf');
    expect(Job.advertStorageName('Ŝcan/ïmage?.jpeg', 'jpg'), '-can-mage-.jpg');
    expect(Job.advertStorageName('???.pdf', 'pdf'), 'Job advert.pdf');
    expect(Job.advertNameFromUrl('https://x.supabase.co/storage/v1/object/public/job-adverts/u1/1730000000/AHF%20Nurse%20Advert.pdf'), 'AHF Nurse Advert.pdf');
    expect(Job.advertNameFromUrl('https://x.supabase.co/storage/v1/object/public/job-adverts/u1/1730000000-advert.pdf'), 'Job advert.pdf');
  });

  test('locations in the same area match each other', () {
    expect(sameAreaAs('Freetown'), containsAll(['Western Area Urban', 'Waterloo']));
    expect(sameAreaAs('Koidu'), {'Kono', 'Koidu'});
    expect(sameAreaAs('Bo'), {'Bo'});
    const f = JobFilter(locations: {'Freetown'});
    expect(f.areaLocations, contains('Western Area Urban'));
  });

  test('jobs are matched to the profile: area, headline and job type', () {
    final job = Job(
      id: 'j1',
      title: 'Public Health Officer',
      companyId: 'c1',
      location: 'Freetown',
      employmentType: EmploymentType.contract,
      workMode: WorkMode.onsite,
      industry: Industry.healthcare,
      experienceLevel: ExperienceLevel.mid,
      postedAt: now,
      deadline: now.add(const Duration(days: 20)),
      salaryMin: null,
      salaryMax: null,
      about: '',
      description: '',
      responsibilities: const [],
      requirements: const [],
      preferred: const [],
      skills: const [],
      benefits: const [],
    );
    const user = AppUser(
      id: 'u1',
      fullName: 'Aminata Kamara',
      email: 'a@example.com',
      headline: 'Public Health Student',
      location: 'Western Area Urban',
      preferences: JobPreferences(employmentTypes: {EmploymentType.contract}),
    );
    final m = JobMatch.of(job, user);
    expect(m.isGood, isTrue);
    expect(m.reasons, contains('In Freetown'));
    expect(m.reasons.any((r) => r.contains('health')), isTrue);
    expect(m.reasons, contains('Contract'));

    const elsewhere = AppUser(id: 'u2', fullName: 'Musa Sesay', email: 'm@example.com', location: 'Kenema', headline: 'Driver');
    expect(JobMatch.of(job, elsewhere).isGood, isFalse);
    expect(JobMatch.recommend([job], user), [job]);
    expect(JobMatch.recommend([job], elsewhere), isEmpty);
  });
}
