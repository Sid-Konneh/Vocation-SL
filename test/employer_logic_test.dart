import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocation_sl/employer/insights.dart';
import 'package:vocation_sl/models/models.dart';

import 'package:vocation_sl/employer/data/demo_employer_backend.dart';

Job _job(String id, {JobStatus status = JobStatus.published, int views = 0, DateTime? deadline}) => Job(
      id: id,
      title: 'Job $id',
      companyId: 'co-1',
      location: 'Bo',
      employmentType: EmploymentType.fullTime,
      workMode: WorkMode.onsite,
      industry: Industry.finance,
      experienceLevel: ExperienceLevel.mid,
      salaryMin: 4000,
      salaryMax: 6000,
      postedAt: DateTime(2026, 9, 1),
      deadline: deadline ?? DateTime.now().add(const Duration(days: 20)),
      about: 'a',
      description: 'd',
      responsibilities: const ['r'],
      requirements: const ['q'],
      preferred: const [],
      skills: const ['Excel'],
      benefits: const [],
      status: status,
      views: views,
    );

JobApplication _app(String id, String jobId, ApplicationStatus status, {required DateTime at, List<StatusEvent>? history}) => JobApplication(
      id: id,
      jobId: jobId,
      userId: 'u$id',
      status: status,
      submittedAt: at,
      history: history ?? [StatusEvent(status: ApplicationStatus.applied, at: at)],
      applicant: ApplicantInfo(fullName: 'Person $id', email: '$id@x.sl', phone: '', location: 'Bo'),
      resume: Resume(id: 'r', fileName: 'cv.pdf', sizeBytes: 1, uploadedAt: at, format: DocumentFormat.pdf),
    );

void main() {
  final now = DateTime(2026, 10, 7, 12);

  group('HiringStats', () {
    final jobs = [
      _job('a', views: 100),
      _job('b', views: 50),
      _job('c', status: JobStatus.draft),
      _job('d', status: JobStatus.pending),
    ];
    final apps = [
      _app('1', 'a', ApplicationStatus.applied, at: now.subtract(const Duration(days: 1))),
      _app('2', 'a', ApplicationStatus.interview, at: now.subtract(const Duration(days: 10)), history: [
        StatusEvent(status: ApplicationStatus.applied, at: now.subtract(const Duration(days: 10))),
        StatusEvent(status: ApplicationStatus.viewed, at: now.subtract(const Duration(days: 8))),
        StatusEvent(status: ApplicationStatus.shortlisted, at: now.subtract(const Duration(days: 6))),
        StatusEvent(status: ApplicationStatus.interview, at: now.subtract(const Duration(days: 2))),
      ]),
      _app('3', 'b', ApplicationStatus.rejected, at: now.subtract(const Duration(days: 3)), history: [
        StatusEvent(status: ApplicationStatus.applied, at: now.subtract(const Duration(days: 3))),
        StatusEvent(status: ApplicationStatus.viewed, at: now.subtract(const Duration(days: 2))),
        StatusEvent(status: ApplicationStatus.rejected, at: now.subtract(const Duration(days: 1))),
      ]),
      _app('4', 'b', ApplicationStatus.withdrawn, at: now.subtract(const Duration(days: 40))),
    ];
    final s = HiringStats(jobs: jobs, applications: apps, now: now);

    test('job and applicant counts', () {
      expect(s.liveJobs, 2);
      expect(s.pendingJobs, 1);
      expect(s.draftJobs, 1);
      expect(s.totalApplicants, 3, reason: 'withdrawn excluded');
      expect(s.newThisWeek, 2);
      expect(s.awaitingReview, 1);
      expect(s.totalViews, 150);
    });

    test('funnel counts everyone who reached each stage', () {
      final f = s.funnel;
      expect(f[ApplicationStatus.applied], 4);
      expect(f[ApplicationStatus.viewed], 2);
      expect(f[ApplicationStatus.shortlisted], 1);
      expect(f[ApplicationStatus.interview], 1);
      expect(f[ApplicationStatus.hired], 0);
    });

    test('daily applications cover the window and sum correctly', () {
      final d = s.dailyApplications(days: 30);
      expect(d.length, 30);
      expect(d.last.day, DateTime(2026, 10, 7));
      expect(d.fold(0, (t, e) => t + e.count), 3, reason: 'the 40-day-old one is outside the window');
    });

    test('average response time uses the first employer action', () {
      // app 2: 2 days to "viewed"; app 3: 1 day to "viewed" -> 1.5
      expect(s.averageResponseDays, closeTo(1.5, 0.01));
    });

    test('job performance excludes drafts and computes conversion', () {
      final p = s.jobPerformance;
      expect(p.map((e) => e.job.id), isNot(contains('c')));
      final a = p.firstWhere((e) => e.job.id == 'a');
      expect(a.applicants, 2);
      expect(a.shortlisted, 1);
      expect(a.conversion, closeTo(0.02, 1e-9));
      expect(p.firstWhere((e) => e.job.id == 'd').conversion, isNull);
    });
  });

  group('models', () {
    test('job status survives a cache round trip', () {
      final j = _job('x', status: JobStatus.pending, views: 7);
      final back = Job.fromJson(j.toJson());
      expect(back.status, JobStatus.pending);
      expect(back.views, 7);
    });

    test('company employer JSON never includes status or ownership', () {
      const c = Company(id: 'c', name: 'Acme', industry: Industry.ngo, location: 'Bo', about: '', size: '', founded: 0, website: '', brandColor: 0);
      final j = c.toEmployerJson();
      expect(j.containsKey('status'), isFalse);
      expect(j.containsKey('verified'), isFalse);
      expect(j.containsKey('owner_id'), isFalse);
    });

    test('company fields sent on save all exist in the companies table', () {
      // Columns created by schema.sql + employer_schema.sql. A key missing here
      // makes Supabase reject the whole insert/update.
      const columns = {
        'id', 'name', 'industry', 'location', 'about', 'size', 'founded', 'website', 'brand_color', 'verified',
        'created_at', 'owner_id', 'status', 'email', 'phone', 'address',
      };
      const c = Company(id: 'c', name: 'Acme', industry: Industry.ngo, location: 'Bo', about: '', size: '', founded: 0, website: '', brandColor: 0);
      expect(columns.containsAll(c.toEmployerJson().keys), isTrue, reason: '${c.toEmployerJson().keys.where((k) => !columns.contains(k))}');
    });
  });

  group('fake backend mirrors database rules', () {
    test('pending company: a posted job waits for approval', () async {
      final b = DemoEmployerBackend();
      await b.registerCompany(const Company(id: '', name: 'Acme', industry: Industry.ngo, location: 'Bo', about: '', size: '', founded: 0, website: '', brandColor: 0));
      final job = await b.saveJob(_job('').copyWithCompany('co-1'), status: JobStatus.published);
      expect(job.status, JobStatus.pending);
    });

    test('approved company: a posted job goes live; drafts stay drafts', () async {
      final b = DemoEmployerBackend(approveOnRegister: true);
      await b.registerCompany(const Company(id: '', name: 'Acme', industry: Industry.ngo, location: 'Bo', about: '', size: '', founded: 0, website: '', brandColor: 0));
      expect((await b.saveJob(_job('').copyWithCompany('co-1'), status: JobStatus.published)).status, JobStatus.published);
      expect((await b.saveJob(_job('').copyWithCompany('co-1'), status: JobStatus.draft)).status, JobStatus.draft);
    });

    test('logo upload is stored on the company and never sent with profile saves', () async {
      final b = DemoEmployerBackend(approveOnRegister: true);
      final c = await b.registerCompany(const Company(id: '', name: 'Acme', industry: Industry.ngo, location: 'Bo', about: '', size: '', founded: 0, website: '', brandColor: 0));
      final withLogo = await b.uploadLogo(c, Uint8List.fromList([137, 80, 78, 71]), 'logo.png');
      expect(withLogo.logoUrl, startsWith('data:image/png;base64,'));
      expect(withLogo.toEmployerJson().containsKey('logo_url'), isFalse, reason: 'saved separately so profile saves work without the logo column');
      expect(Company.fromJson({...withLogo.toJson(), 'id': 'x'}).logoUrl, withLogo.logoUrl, reason: 'survives the cache');
    });

    test('employers cannot set a candidate to withdrawn', () async {
      final b = DemoEmployerBackend(approveOnRegister: true);
      await b.registerCompany(const Company(id: '', name: 'Acme', industry: Industry.ngo, location: 'Bo', about: '', size: '', founded: 0, website: '', brandColor: 0));
      final job = await b.saveJob(_job('').copyWithCompany('co-1'), status: JobStatus.published);
      final app = b.addApplicant(job.id, 'Test Person');
      expect(() => b.updateApplication(app, status: ApplicationStatus.withdrawn), throwsA(isA<Exception>()));
    });
  });
}

extension on Job {
  Job copyWithCompany(String id) => Job(
        id: '',
        title: title,
        companyId: id,
        location: location,
        employmentType: employmentType,
        workMode: workMode,
        industry: industry,
        experienceLevel: experienceLevel,
        salaryMin: salaryMin,
        salaryMax: salaryMax,
        postedAt: postedAt,
        deadline: deadline,
        about: about,
        description: description,
        responsibilities: responsibilities,
        requirements: requirements,
        preferred: preferred,
        skills: skills,
        benefits: benefits,
      );
}
