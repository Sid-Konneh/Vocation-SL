import 'package:flutter_test/flutter_test.dart';
import 'package:vocation_sl/models/models.dart';

final _now = DateTime(2026, 11, 22, 10);

Job _job({int applicants = 0, String applyUrl = '', int postedDaysAgo = 1, int deadlineInDays = 10, JobStatus status = JobStatus.published}) => Job(
      id: 'j1',
      title: 'Accounts Assistant',
      companyId: 'c1',
      location: 'Bo',
      employmentType: EmploymentType.fullTime,
      workMode: WorkMode.onsite,
      industry: Industry.finance,
      experienceLevel: ExperienceLevel.entry,
      salaryMin: null,
      salaryMax: null,
      postedAt: _now.subtract(Duration(days: postedDaysAgo)),
      deadline: _now.add(Duration(days: deadlineInDays)),
      about: '',
      description: '',
      responsibilities: const [],
      requirements: const [],
      preferred: const [],
      skills: const [],
      benefits: const [],
      applyUrl: applyUrl,
      applicants: applicants,
      status: status,
    );

void main() {
  group('applicant momentum', () {
    test('in-app jobs use the real applicant count', () {
      expect(JobSignals.momentum(_job(), now: _now), 'Be the first to apply');
      expect(JobSignals.momentum(_job(applicants: 1), now: _now), 'Be an early applicant: 1 person has applied');
      expect(JobSignals.momentum(_job(applicants: 9), now: _now), 'Be an early applicant: 9 people have applied');
      expect(JobSignals.momentum(_job(applicants: 24), now: _now), '24 people have applied');
    });

    test('external jobs never show a count; only new ones get a prompt', () {
      expect(JobSignals.momentum(_job(applyUrl: 'https://x.org', postedDaysAgo: 1), now: _now), 'New: be one of the first to apply');
      expect(JobSignals.momentum(_job(applyUrl: 'mailto:hr@x.org', postedDaysAgo: 5), now: _now), isNull);
    });

    test('nothing on closed or expired jobs', () {
      expect(JobSignals.momentum(_job(status: JobStatus.closed), now: _now), isNull);
      expect(JobSignals.momentum(_job(deadlineInDays: -1), now: _now), isNull);
    });
  });

  group('responsive employer', () {
    test('needs enough replies, most applicants answered, and a reply within a week', () {
      expect(JobSignals.isResponsive(const ReplySpeed(applications: 10, replied: 8, medianHours: 50)), isTrue);
      expect(JobSignals.isResponsive(const ReplySpeed(applications: 10, replied: 8, medianHours: 200)), isFalse, reason: 'too slow');
      expect(JobSignals.isResponsive(const ReplySpeed(applications: 10, replied: 4, medianHours: 20)), isFalse, reason: 'most never heard back');
      expect(JobSignals.isResponsive(const ReplySpeed(applications: 2, replied: 2, medianHours: 5)), isFalse, reason: 'too few to judge');
      expect(JobSignals.isResponsive(ReplySpeed.unknown), isFalse);
    });

    test('label says how fast', () {
      expect(JobSignals.responsiveLabel(const ReplySpeed(applications: 10, replied: 8, medianHours: 50)), 'Usually replies in about 2 days');
      expect(JobSignals.responsiveLabel(const ReplySpeed(applications: 5, replied: 5, medianHours: 6)), 'Usually replies within a day');
    });
  });
}
