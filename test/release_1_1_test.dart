import 'package:flutter_test/flutter_test.dart';
import 'package:vocation_sl/admin/features/traction.dart';
import 'package:vocation_sl/admin/scam_flags.dart';
import 'package:vocation_sl/employer/data/demo_employer_backend.dart';
import 'package:vocation_sl/employer/features/candidates/candidates_screen.dart';
import 'package:vocation_sl/models/models.dart';
import 'package:vocation_sl/services/export_service.dart';

Job _job({String description = 'A good job.', String applyUrl = '', List<ScreeningQuestion> screening = const [], int? salaryMax}) => Job(
      id: 'j1',
      title: 'Accounts Assistant',
      companyId: 'c1',
      location: 'Bo',
      employmentType: EmploymentType.fullTime,
      workMode: WorkMode.onsite,
      industry: Industry.finance,
      experienceLevel: ExperienceLevel.entry,
      salaryMin: null,
      salaryMax: salaryMax,
      postedAt: DateTime(2026, 10, 1),
      deadline: DateTime(2026, 11, 1),
      about: 'Keep the books.',
      description: description,
      responsibilities: const [],
      requirements: const [],
      preferred: const [],
      skills: const [],
      benefits: const [],
      applyUrl: applyUrl,
      screening: screening,
    );

JobApplication _app(String id, {Map<String, bool> answers = const {}, ApplicationStatus status = ApplicationStatus.applied, DateTime? at, Job? job}) => JobApplication(
      id: id,
      jobId: 'j1',
      userId: 'u$id',
      status: status,
      submittedAt: at ?? DateTime(2026, 10, 5),
      history: [StatusEvent(status: status, at: at ?? DateTime(2026, 10, 5))],
      applicant: const ApplicantInfo(fullName: 'Fatmata Kamara', email: 'f@example.com', phone: '076000000', location: 'Bo'),
      resume: Resume(id: 'r', fileName: 'cv.pdf', sizeBytes: 1, uploadedAt: DateTime(2026, 10, 1), format: DocumentFormat.pdf),
      screeningAnswers: answers,
      job: job,
    );

void main() {
  group('scam flags', () {
    test('a normal job is not flagged', () => expect(scamFlags(_job()), isEmpty));
    test('fees, WhatsApp-only contact and shortened links are flagged', () {
      expect(scamFlags(_job(description: 'Pay a registration fee of Le 200 before your interview.')), contains('Mentions fees or payment from candidates'));
      expect(scamFlags(_job(description: 'Apply now on wa.me/23276000000')), contains('Asks candidates to apply or pay by WhatsApp'));
      expect(scamFlags(_job(applyUrl: 'https://bit.ly/abc')), contains('Application link is a shortened link'));
      expect(scamFlags(_job(salaryMax: 400000)), contains('Very high salary for an entry-level job'));
    });
  });

  test('screening match counts only questions with a wanted answer', () {
    final job = _job(screening: const [
      ScreeningQuestion(id: 'q1', text: 'Driving licence?', wanted: true),
      ScreeningQuestion(id: 'q2', text: 'Can start in November?', wanted: true),
      ScreeningQuestion(id: 'q3', text: 'Ever worked in Bo?'),
    ]);
    final a = _app('1', answers: {'q1': true, 'q2': false, 'q3': true}, job: job);
    expect(a.screeningMatch(null), (matched: 1, total: 2));
    expect(JobApplication.fromJson(a.toJson()).screeningAnswers, {'q1': true, 'q2': false, 'q3': true});
    expect(Job.fromJson(job.toJson()).screening.map((q) => q.wanted), [true, true, null]);
  });

  test('message templates fill in the first name, job and company', () {
    final text = fillTemplate(messageTemplates[ApplicationStatus.interview]!, name: 'Fatmata Kamara', job: 'Accounts Assistant', company: 'Aion Health SL');
    expect(text, startsWith('Dear Fatmata,'));
    expect(text, contains('Accounts Assistant'));
    expect(text, endsWith('Aion Health SL'));
  });

  test('CSV export quotes commas, quotes and new lines', () {
    expect(ExportService.csv(['a', 'b'], [
      ['x, y', 'say "hi"'],
      [1, null],
    ]), 'a,b\r\n"x, y","say ""hi"""\r\n1,');
  });

  test('platform settings keep prices and the launch offer', () {
    final s = PlatformSettings(postingPrice: 5000, featuredPrice: 1500, launchFreePosts: 5, launchUntil: DateTime(2026, 12, 31));
    final back = PlatformSettings.fromRows(s.toRows());
    expect(back.postingPrice, 5000);
    expect(back.featuredPrice, 1500);
    expect(back.launchFreePosts, 5);
    expect(back.launchUntil, DateTime(2026, 12, 31));
    expect(back.launchActiveOn(DateTime(2026, 12, 31, 18)), isTrue);
    expect(back.launchActiveOn(DateTime(2027, 1, 1)), isFalse);
  });

  test('launch offer counts remaining free postings', () {
    final o = LaunchOffer.fromJson({'free_posts': 5, 'used': 2, 'until': '2026-12-31', 'active': true});
    expect(o.remaining, 3);
    expect(o.available, isTrue);
    expect(LaunchOffer.fromJson({'free_posts': 5, 'used': 5, 'active': true}).available, isFalse);
  });

  test('demo team: owner adds and removes a recruiter', () async {
    final b = DemoEmployerBackend();
    await b.addTeamMember('hr@example.com');
    expect((await b.team()).map((m) => m.role), ['owner', 'recruiter']);
    await b.removeTeamMember('u-hr@example.com');
    expect(await b.team(), hasLength(1));
  });

  test('traction report counts real activity by month', () {
    final now = DateTime(2026, 10, 20);
    final users = [
      AdminUser(id: 'a', email: 'a@x.com', name: 'A', role: 'seeker', createdAt: DateTime(2026, 10, 2), location: 'Bo', lastSeenAt: DateTime(2026, 10, 19)),
      AdminUser(id: 'b', email: 'b@x.com', name: 'B', role: 'seeker', createdAt: DateTime(2026, 9, 10), location: 'Freetown'),
      AdminUser(id: 'c', email: 'c@x.com', name: 'C', role: 'employer', createdAt: DateTime(2026, 10, 3)),
    ];
    final t = TractionReport.compute(
      users: users,
      companies: const [],
      jobs: [_job()],
      applications: [_app('1', at: DateTime(2026, 10, 6)), _app('2', status: ApplicationStatus.hired, at: DateTime(2026, 10, 9))],
      invoices: const [],
      referrals: const [],
      now: now,
    );
    expect(t.seekers, 2);
    expect(t.employerUsers, 1);
    expect(t.months.last.seekers, 1);
    expect(t.months[t.months.length - 2].seekers, 1);
    expect(t.applications, 2);
    expect(t.hires, 1);
    expect(t.activeUsers30d, 1);
    expect(t.seekersOutsideWestern, 1);
    expect(t.summary(), contains('2 job seekers'));
  });
}
