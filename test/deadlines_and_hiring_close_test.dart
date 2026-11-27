import 'package:flutter_test/flutter_test.dart';
import 'package:vocation_sl/core/errors.dart';
import 'package:vocation_sl/data/backend/message_backend.dart';
import 'package:vocation_sl/models/models.dart';

Job _job({required DateTime deadline, JobStatus status = JobStatus.published}) => Job(
      id: 'j-1',
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
      about: '',
      description: '',
      responsibilities: const [],
      requirements: const [],
      preferred: const [],
      skills: const [],
      benefits: const [],
      status: status,
    );

void main() {
  group('applications after the deadline', () {
    test('a live job before its deadline takes applications', () {
      expect(_job(deadline: DateTime.now().add(const Duration(days: 3))).acceptsApplications, isTrue);
    });

    test('no applications once the deadline has passed', () {
      expect(_job(deadline: DateTime.now().subtract(const Duration(minutes: 1))).acceptsApplications, isFalse);
    });

    test('extending the deadline opens applications again', () {
      final expired = _job(deadline: DateTime.now().subtract(const Duration(days: 1)));
      final extended = _job(deadline: expired.deadline.add(const Duration(days: 8)));
      expect(expired.acceptsApplications, isFalse);
      expect(extended.acceptsApplications, isTrue);
    });

    test('a closed job takes no applications even before its deadline', () {
      expect(_job(deadline: DateTime.now().add(const Duration(days: 3)), status: JobStatus.closed).acceptsApplications, isFalse);
    });
  });

  group('closing a hiring process', () {
    test('closing turns messages off; reopening turns them back on', () async {
      final b = DemoMessageBackend();
      await b.send('a-1', 'Thank you for your interview.', asEmployer: true);

      await b.setProcessClosed('a-1', true);
      final closed = await b.blockStatus('a-1');
      expect(closed.processClosed, isTrue);
      expect(closed.messagesOff, isTrue);
      expect(closed.processClosedAt, isNotNull);
      expect(() => b.send('a-1', 'One more thing', asEmployer: true), throwsA(isA<ValidationException>()));

      await b.setProcessClosed('a-1', false);
      final open = await b.blockStatus('a-1');
      expect(open.processClosed, isFalse);
      expect(open.messagesOff, isFalse);
      await b.send('a-1', 'We have news about the role.', asEmployer: true);
      expect((await b.thread('a-1')).length, 2);
    });

    test('closing one candidate does not affect another', () async {
      final b = DemoMessageBackend();
      await b.setProcessClosed('a-1', true);
      expect((await b.blockStatus('a-2')).messagesOff, isFalse);
    });
  });
}
