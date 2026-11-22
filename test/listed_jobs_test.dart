import 'package:flutter_test/flutter_test.dart';
import 'package:vocation_sl/admin/features/listed_jobs.dart';
import 'package:vocation_sl/models/models.dart';

const _vsl = Company(id: 'vsl', name: 'Vocation SL', industry: Industry.ngo, location: 'Bo', about: '', size: '', founded: 0, website: '', brandColor: 0);
const _other = Company(id: 'c2', name: 'Kroo Town Traders', industry: Industry.finance, location: 'Bo', about: '', size: '', founded: 0, website: '', brandColor: 0);

Job _job(String id, String title, {Company company = _vsl, String applyUrl = 'mailto:hr@example.org', int views = 100, int taps = 20, int applied = 3, int daysLeft = 5}) => Job(
      id: id,
      title: title,
      companyId: company.id,
      company: company,
      location: 'Freetown',
      employmentType: EmploymentType.fullTime,
      workMode: WorkMode.onsite,
      industry: Industry.ngo,
      experienceLevel: ExperienceLevel.mid,
      salaryMin: null,
      salaryMax: null,
      postedAt: DateTime.now(),
      deadline: DateTime.now().add(Duration(days: daysLeft)),
      about: '',
      description: '',
      responsibilities: const [],
      requirements: const [],
      preferred: const [],
      skills: const [],
      benefits: const [],
      applyUrl: applyUrl,
      views: views,
      applyClicks: taps,
      externalApplied: applied,
      status: JobStatus.published,
    );

void main() {
  test('splits "Role (Employer)" titles', () {
    expect(splitListedTitle('Civil Engineer (LOMTIBUL Construction)'), (role: 'Civil Engineer', employer: 'LOMTIBUL Construction'));
    expect(splitListedTitle('Driver').employer, '');
  });

  test('groups team-listed jobs by employer and leaves employers\' own jobs out', () {
    final list = ListedEmployer.from([
      _job('1', 'Civil Engineer (LOMTIBUL Construction)', views: 50),
      _job('2', 'Receptionist (LOMTIBUL Construction)', views: 30),
      _job('3', 'MEAL Manager (Welthungerhilfe)', applyUrl: 'https://career5.successfactors.eu/x', views: 200),
      _job('4', 'Accountant (Someone)', company: _other),
      _job('5', 'Old job (BRAC)', daysLeft: -3),
    ], includeClosed: false);
    expect(list.map((e) => e.name), ['Welthungerhilfe', 'LOMTIBUL Construction']);
    final lomtibul = list[1];
    expect(lomtibul.jobs.length, 2);
    expect(lomtibul.views, 80);
    expect(lomtibul.email, 'hr@example.org');
    expect(list[0].website, 'career5.successfactors.eu');
    expect(ListedEmployer.from([_job('5', 'Old job (BRAC)', daysLeft: -3)], includeClosed: true).single.name, 'BRAC');
  });

  test('the message uses the real numbers and mentions the free offer only while it lasts', () {
    final e = ListedEmployer('LOMTIBUL Construction', [_job('1', 'Civil Engineer (LOMTIBUL Construction)', views: 140, taps: 30, applied: 6)]);
    final msg = e.message(freeUntil: DateTime.now().add(const Duration(days: 10)));
    expect(msg, contains('Hello LOMTIBUL Construction team'));
    expect(msg, contains('Civil Engineer: 140 views, 30 taps on Apply, 6 told us they applied'));
    expect(msg, contains('It is free until'));
    expect(e.message(freeUntil: DateTime(2020)), isNot(contains('free until')));
  });
}
