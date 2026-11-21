import 'package:flutter_test/flutter_test.dart';
import 'package:vocation_sl/employer/data/demo_employer_backend.dart';
import 'package:vocation_sl/models/models.dart';

Job _job(DateTime deadline) => Job(
      id: '',
      title: 'Store Accountant',
      companyId: 'co-1',
      location: 'Bo',
      employmentType: EmploymentType.fullTime,
      workMode: WorkMode.onsite,
      industry: Industry.finance,
      experienceLevel: ExperienceLevel.entry,
      salaryMin: null,
      salaryMax: null,
      postedAt: DateTime.now(),
      deadline: deadline,
      about: 'Keep the books.',
      description: 'Keep the books for our shop.',
      responsibilities: const [],
      requirements: const [],
      preferred: const [],
      skills: const [],
      benefits: const [],
    );

DemoEmployerBackend _approved() => DemoEmployerBackend()
  ..company = const Company(
    id: 'co-1',
    name: 'Kroo Town Traders',
    industry: Industry.finance,
    location: 'Bo',
    about: '',
    size: '',
    founded: 0,
    website: '',
    brandColor: 0,
    status: CompanyStatus.approved,
  );

void main() {
  group('extend or repost a job', () {
    test('a live job is extended from its current deadline', () async {
      final b = _approved();
      final deadline = DateTime.now().add(const Duration(days: 3));
      final job = await b.saveJob(_job(deadline), status: JobStatus.published);
      final r = await b.extendJob(job.id, 2);
      expect(r.status, JobStatus.published);
      expect(DateTime(r.deadline.year, r.deadline.month, r.deadline.day), DateTime(deadline.year, deadline.month, deadline.day + 14));
      expect(r.amount, 2000);
    });

    test('a closed job past its deadline is reposted from today', () async {
      final b = _approved();
      final job = await b.saveJob(_job(DateTime.now().subtract(const Duration(days: 10))), status: JobStatus.published);
      await b.setJobStatus(job.id, JobStatus.closed);
      final r = await b.extendJob(job.id, 1);
      final today = DateTime.now();
      expect(r.status, JobStatus.published);
      expect(DateTime(r.deadline.year, r.deadline.month, r.deadline.day), DateTime(today.year, today.month, today.day + 7));
    });

    test('only 1 to 4 weeks, and drafts can\'t be extended', () async {
      final b = _approved();
      final draft = await b.saveJob(_job(DateTime.now().add(const Duration(days: 5))), status: JobStatus.draft);
      expect(() => b.extendJob(draft.id, 1), throwsA(isA<Exception>()));
      final live = await b.saveJob(_job(DateTime.now().add(const Duration(days: 5))), status: JobStatus.published);
      expect(() => b.extendJob(live.id, 5), throwsA(isA<Exception>()));
    });
  });

  test('platform settings read and write the weekly extension price', () {
    final s = PlatformSettings.fromRows([
      {'key': 'extension_price', 'value': 1000},
    ]);
    expect(s.extensionPrice, 1000);
    final back = PlatformSettings.fromRows(s.copyWith(extensionPrice: 1200).toRows());
    expect(back.extensionPrice, 1200);
    expect(const PlatformSettings().extensionPrice, 1000);
  });
}
