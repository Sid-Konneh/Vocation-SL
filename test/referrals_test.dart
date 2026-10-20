import 'package:flutter_test/flutter_test.dart';
import 'package:vocation_sl/core/errors.dart';
import 'package:vocation_sl/data/backend/referral_backend.dart';
import 'package:vocation_sl/models/models.dart';
import 'package:vocation_sl/services/file_service.dart';
import 'package:vocation_sl/services/share_service.dart';

void main() {
  group('ReferralCode', () {
    test('matches codes typed with spaces, dashes or lower case', () {
      expect(ReferralCode.normalize(' vsl-7kq 2m '), 'VSL7KQ2M');
      expect(ReferralCode.display('vsl7kq2m'), 'VSL-7KQ2M');
    });

    test('builds the employer sign-up link', () {
      expect(ReferralCode.link('VSL-7KQ2M'), 'https://employers.vocationsl.com/r/VSL7KQ2M');
    });
  });

  group('DemoReferralBackend', () {
    test('creates one stable code per user', () async {
      final b = DemoReferralBackend();
      final code = await b.myCode();
      expect(code, matches(RegExp(r'^VSL[A-Z2-9]{5}$')));
      expect(await b.myCode(), code);
    });

    test('a company can be referred once, and not with your own code', () async {
      final b = DemoReferralBackend(userId: 'seeker-1');
      final code = await b.myCode();
      await b.claim(ReferralCode.display(code).toLowerCase(), 'co-1', asUser: 'employer-1', companyName: 'Aion Health SL');
      await b.claim(code, 'co-1', asUser: 'employer-1'); // ignored, already referred
      final mine = await b.myReferrals();
      expect(mine, hasLength(1));
      expect(mine.single.companyName, 'Aion Health SL');
      expect(mine.single.status, ReferralStatus.signedUp);

      expect(() => b.claim(code, 'co-2', asUser: 'seeker-1'), throwsA(isA<ValidationException>()));
      expect(() => b.claim('VSL-NOPE9', 'co-3'), throwsA(isA<ValidationException>()));
    });

    test('admins mark referrals rewarded', () async {
      final b = DemoReferralBackend();
      await b.claim(await b.myCode(), 'co-1');
      final r = (await b.allReferrals()).single;
      await b.setStatus(r.id, ReferralStatus.rewarded, note: 'Airtime sent');
      final updated = (await b.allReferrals()).single;
      expect(updated.status, ReferralStatus.rewarded);
      expect(updated.note, 'Airtime sent');
      expect(updated.rewardedAt, isNotNull);
    });
  });

  test('referral totals count companies and the jobs they posted', () {
    Referral r(String id, ReferralStatus s, int jobs) => Referral(
          id: id,
          referrerId: 'u',
          companyId: 'c$id',
          companyName: 'Co $id',
          code: 'VSLAAAAA',
          status: s,
          createdAt: DateTime(2026, 10, 1),
          jobs: [for (var i = 0; i < jobs; i++) ReferralJob(jobId: 'j$id$i', title: 'Job $i', publishedAt: DateTime(2026, 10, 2))],
        );
    final s = ReferralSummary([
      r('1', ReferralStatus.signedUp, 0),
      r('2', ReferralStatus.qualified, 3),
      r('3', ReferralStatus.rewarded, 2),
      r('4', ReferralStatus.rejected, 5),
    ]);
    expect(s.total, 3);
    expect(s.jobsPosted, 5);
    expect(s.qualified, 2);
    expect(s.rewarded, 1);
  });

  test('referral reads jobs from the database row', () {
    final r = Referral.fromJson({
      'id': 'r1',
      'referrer_id': 'u1',
      'company_id': 'c1',
      'company_name': 'ConFam Enterprise',
      'code': 'VSLAB234',
      'status': 'qualified',
      'created_at': '2026-10-09T10:00:00Z',
      'jobs': [
        {'id': 'j1', 'title': 'Accountant', 'published_at': '2026-10-10T09:00:00Z'},
      ],
    });
    expect(r.jobsPosted, 1);
    expect(r.jobs.single.title, 'Accountant');
    expect(r.status, ReferralStatus.qualified);
  });

  group('Mobile Money payout', () {
    test('accepts Sierra Leone numbers in any common format', () {
      for (final n in ['076 123 456', '+232 76 123 456', '23276123456', '76123456']) {
        expect(PayoutDetails.localDigits(n), '76123456', reason: n);
      }
      expect(PayoutDetails.localDigits('0761234'), isNull);
      const p = PayoutDetails(provider: MobileMoneyProvider.orange, number: '+23276123456', accountName: 'Aminata Kamara');
      expect(p.displayNumber, '076 123 456');
      expect(p.summary, 'Orange Money · 076 123 456 · Aminata Kamara');
    });

    test('admins see where to pay each referrer', () async {
      final b = DemoReferralBackend(userId: 'seeker-1');
      await b.savePayout(MobileMoneyProvider.africell, '088 765 432', 'Mohamed Sesay');
      await b.claim(await b.myCode(), 'co-1');
      expect((await b.myPayout())?.number, '+23288765432');
      expect((await b.allReferrals()).single.payout?.provider, MobileMoneyProvider.africell);
      expect(() => b.savePayout(MobileMoneyProvider.orange, '12345', 'X Y Z'), throwsA(isA<ValidationException>()));
    });
  });

  test('applications keep up to 5 supporting PDFs and jobs say which documents to attach', () {
    final job = Job.fromJson({
      'id': 'j1',
      'title': 'Nurse',
      'company_id': 'c1',
      'posted_at': '2026-10-01T00:00:00Z',
      'deadline': '2026-11-01T00:00:00Z',
      'documents_requested': true,
      'documents_note': 'Nursing licence and ID',
    });
    expect(job.documentsRequested, isTrue);
    expect(Job.fromJson(job.toJson()).documentsNote, 'Nursing licence and ID');
    expect(Job.fromJson({...job.toJson(), 'documents_requested': null}).documentsRequested, isFalse, reason: 'older jobs');

    final app = JobApplication(
      id: 'a1',
      jobId: 'j1',
      userId: 'u1',
      status: ApplicationStatus.applied,
      submittedAt: DateTime(2026, 10, 15),
      history: const [],
      applicant: const ApplicantInfo(fullName: 'Fatmata K', email: 'f@example.com', phone: '076000000', location: 'Freetown'),
      resume: Resume(id: 'r', fileName: 'cv.pdf', sizeBytes: 1, uploadedAt: DateTime(2026, 10, 15), format: DocumentFormat.pdf),
      supportingDocuments: const [
        SupportingDocument(id: 'd1', fileName: 'licence.pdf', sizeBytes: 2048, storagePath: 'u1/licence.pdf'),
        SupportingDocument(id: 'd2', fileName: 'id.pdf', sizeBytes: 1024, storagePath: 'u1/id.pdf'),
      ],
    );
    final back = JobApplication.fromJson(app.toJson());
    expect(back.supportingDocuments.map((d) => d.fileName), ['licence.pdf', 'id.pdf']);
    expect(back.copyWith(status: ApplicationStatus.viewed).supportingDocuments, hasLength(2));
    expect(JobApplication.fromJson({...app.toJson()}..remove('supporting_documents')).supportingDocuments, isEmpty, reason: 'older applications');
    expect(SupportingDocument.maxPerApplication, 5);
  });

  test('jobs can send candidates to an external application link', () {
    expect(Job.normalizeApplyUrl('careers.example.org/jobs/12'), 'https://careers.example.org/jobs/12');
    expect(Job.normalizeApplyUrl('  http://example.com/apply '), 'http://example.com/apply');
    expect(Job.normalizeApplyUrl(''), isNull);
    expect(Job.normalizeApplyUrl('not a link'), isNull);
    expect(Job.normalizeApplyUrl('localhost'), isNull);

    final job = Job.fromJson({
      'id': 'j2',
      'title': 'Driver',
      'company_id': 'c1',
      'posted_at': '2026-10-01T00:00:00Z',
      'deadline': '2026-11-01T00:00:00Z',
      'apply_url': 'https://careers.example.org/jobs/12',
    });
    expect(job.appliesExternally, isTrue);
    expect(job.applyHost, 'careers.example.org');
    expect(Job.fromJson(job.toJson()).applyUrl, 'https://careers.example.org/jobs/12');
    expect(Job.fromJson({...job.toJson()}..remove('apply_url')).appliesExternally, isFalse, reason: 'older jobs apply in the app');
  });

  test('document uploads accept PDF only', () {
    expect(FileService.documentExtensions, ['pdf']);
  });

  test('shared jobs link straight to the job page', () {
    expect(ShareService.jobLink('job-42'), 'https://app.vocationsl.com/job/job-42');
  });
}
