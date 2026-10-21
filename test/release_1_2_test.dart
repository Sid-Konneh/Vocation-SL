import 'package:flutter_test/flutter_test.dart';
import 'package:vocation_sl/data/backend/hiring_backend.dart';
import 'package:vocation_sl/models/models.dart';
import 'package:vocation_sl/services/job_source.dart';

void main() {
  group('interview time slots', () {
    test('employer offers times, applicant picks one, new times replace old ones', () async {
      final b = DemoHiringBackend();
      final t1 = DateTime.now().add(const Duration(days: 2));
      final t2 = DateTime.now().add(const Duration(days: 3));
      await b.proposeInterview('app-1', [t2, t1], place: 'Wilkinson Road');
      var p = (await b.latestProposal('app-1'))!;
      expect(p.isOpen, isTrue);
      expect(p.slots, [t1, t2], reason: 'sorted');
      expect(p.place, 'Wilkinson Road');

      await b.chooseSlot(p.id, t2);
      p = (await b.latestProposal('app-1'))!;
      expect(p.isChosen, isTrue);
      expect(p.chosenAt, t2);
      expect(() => b.chooseSlot(p.id, t1), throwsA(isA<Exception>()), reason: 'already chosen');

      await b.proposeInterview('app-1', [t1]);
      expect(b.proposals.where((x) => x.applicationId == 'app-1' && x.status != InterviewProposalStatus.cancelled).length, 1);
    });

    test('times must be in the future and at most 3', () async {
      final b = DemoHiringBackend();
      final soon = DateTime.now().add(const Duration(days: 1));
      expect(() => b.proposeInterview('a', []), throwsA(isA<Exception>()));
      expect(() => b.proposeInterview('a', [DateTime.now()]), throwsA(isA<Exception>()));
      expect(
        () => b.proposeInterview('a', [for (var i = 0; i < 4; i++) soon.add(Duration(hours: i))]),
        throwsA(isA<Exception>()),
      );
    });

    test('proposal rows parse from the database', () {
      final p = InterviewProposal.fromJson({
        'id': 'x',
        'application_id': 'app-1',
        'slots': ['2026-11-02T10:00:00+00:00', '2026-11-01T14:30:00+00:00'],
        'status': 'chosen',
        'chosen_at': '2026-11-02T10:00:00+00:00',
        'created_at': '2026-10-20T09:00:00Z',
        'place': 'Office',
      });
      expect(p.slots.first.isBefore(p.slots.last), isTrue);
      expect(p.isChosen, isTrue);
    });
  });

  group('reply speed', () {
    test('needs at least 3 replies before showing a figure', () {
      expect(const ReplySpeed(applications: 4, replied: 2, medianHours: 20).hasEnoughData, isFalse);
      final s = ReplySpeed.fromJson({'applications': 10, 'replied': 8, 'median_hours': 52.0, 'replied_within_7_days': 7});
      expect(s.hasEnoughData, isTrue);
      expect(s.typical, 'in about 2 days');
      expect(const ReplySpeed(applications: 5, replied: 5, medianHours: 6).typical, 'within a day');
    });
  });

  group('talent search', () {
    test('summary rows build readable experience and education lines', () {
      final t = TalentProfile.fromJson({
        'user_id': 'u1',
        'full_name': 'Aminata Sesay',
        'skills': ['Excel'],
        'experience': [
          {'title': 'Accountant', 'company': 'Sierra Traders', 'start': '2021-02-01', 'end': null},
        ],
        'education': [
          {'degree': 'BSc', 'field': 'Accounting', 'school': 'Fourah Bay College', 'end_year': 2018},
        ],
        'languages': [
          {'name': 'Krio', 'level': 'Native'},
        ],
        'invited_jobs': ['job-1'],
      });
      expect(t.experience.single, 'Accountant · Sierra Traders (2021 – now)');
      expect(t.education.single, 'BSc Accounting, Fourah Bay College (2018)');
      expect(t.languages.single, 'Krio (Native)');
      expect(t.initials, 'AS');
      expect(t.withInvite('job-2').invitedJobIds, ['job-1', 'job-2']);
    });

    test('an invitation can be sent once per job', () async {
      final b = DemoHiringBackend();
      final found = await b.searchTalent(query: 'accountant');
      expect(found.map((p) => p.userId), contains('t-1'));
      expect(await b.searchTalent(location: 'Bo'), everyElement(predicate<TalentProfile>((p) => p.location == 'Bo')));
      await b.inviteToApply('t-1', 'job-1');
      expect(() => b.inviteToApply('t-1', 'job-1'), throwsA(isA<Exception>()));
      expect((await b.searchTalent(query: 'accountant')).first.invitedJobIds, ['job-1']);
    });

    test('the full talent profile never includes contact details or the CV', () async {
      final b = DemoHiringBackend();
      final u = await b.talentProfile('t-1');
      expect(u.fullName, 'Aminata Sesay');
      expect(u.skills, isNotEmpty);
      expect(u.email, isEmpty);
      expect(u.phone, isEmpty);
      expect(u.resume, isNull);
      expect(() => b.talentProfile('nobody'), throwsA(isA<Exception>()));
    });

    test('job seekers are hidden until they opt in', () async {
      final b = DemoHiringBackend();
      expect(await b.myDiscoverable(), isFalse);
      await b.setDiscoverable(true);
      expect(await b.myDiscoverable(), isTrue);
    });
  });

  group('hiring report', () {
    test('parses sources, stages and speed', () {
      final r = JobReport.fromJson({
        'job_id': 'j1',
        'title': 'Accounts Assistant',
        'views': 200,
        'applications': 10,
        'reached': {'shortlisted': 4, 'interview': 2, 'offer': 1, 'hired': 1},
        'sources': {'home': 5, 'alert': 3, 'unknown': 1, 'something-new': 1},
        'median_reply_hours': 30,
        'by_day': [
          {'day': '2026-10-01', 'n': 3},
        ],
        'generated_at': '2026-10-20T09:00:00Z',
      });
      expect(r.hired, 1);
      expect(r.conversion, 5.0);
      expect(r.sources[ApplicationSource.home], 5);
      expect(r.sources[ApplicationSource.unknown], 2, reason: 'unknown names count as not recorded');
      expect(r.byDay.single.count, 3);
    });

    test('applications remember where the job was found', () {
      JobSource.note('job-9', ApplicationSource.search);
      expect(JobSource.of('job-9'), ApplicationSource.search);
      JobSource.noteOpened('job-10', firstPage: true);
      expect(JobSource.of('job-10'), ApplicationSource.link);
      JobSource.noteFromNotification('job-11', NotificationType.invite);
      expect(JobSource.of('job-11'), ApplicationSource.invite);
      expect(JobSource.fromPath('/saved'), ApplicationSource.saved);
    });
  });

  group('support inbox', () {
    test('a request gets a staff reply and can be closed', () async {
      final b = DemoHiringBackend();
      final id = await b.openTicket(subject: 'Can\'t upload CV', category: SupportCategory.bug, body: 'The upload button does nothing.', side: UserRole.seeker);
      expect((await b.myTickets()).first.status, SupportStatus.open);
      b.replyAsStaff = true;
      await b.replySupport(id, 'Please try again with a PDF under 5 MB.');
      expect((await b.myTickets()).firstWhere((t) => t.id == id).status, SupportStatus.answered);
      expect((await b.supportThread(id)).last.fromStaff, isTrue);
      await b.setSupportStatus(id, SupportStatus.closed);
      expect((await b.allTickets()).firstWhere((t) => t.id == id).status, SupportStatus.closed);
      expect(() => b.openTicket(subject: 'x', category: SupportCategory.other, body: 'short', side: UserRole.seeker), throwsA(isA<Exception>()));
    });
  });

  test('new notification types parse, and older apps fall back safely', () {
    for (final t in ['invite', 'support', 'supportAdmin', 'digest']) {
      final n = AppNotification.fromJson({'id': '1', 'user_id': 'u', 'type': t, 'title': 'x', 'created_at': '2026-10-20T09:00:00Z'});
      expect(n.type.name, t);
    }
  });

  test('applications carry their source through JSON', () {
    final now = DateTime(2026, 10, 20);
    final a = JobApplication(
      id: 'a',
      jobId: 'j',
      userId: 'u',
      status: ApplicationStatus.applied,
      submittedAt: now,
      history: [StatusEvent(status: ApplicationStatus.applied, at: now)],
      applicant: const ApplicantInfo(fullName: 'A', email: 'a@x.sl', phone: '', location: 'Bo'),
      resume: Resume(id: 'r', fileName: 'cv.pdf', sizeBytes: 1, uploadedAt: now, format: DocumentFormat.pdf),
      source: ApplicationSource.alert.name,
    );
    expect(JobApplication.fromJson(a.toJson()).source, 'alert');
  });
}
