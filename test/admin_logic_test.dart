import 'package:flutter_test/flutter_test.dart';
import 'package:vocation_sl/admin/data/demo_admin_backend.dart';
import 'package:vocation_sl/models/models.dart';

void main() {
  group('permissions', () {
    test('approving a company publishes its waiting jobs and is logged', () async {
      final b = DemoAdminBackend();
      expect((await b.jobs()).firstWhere((j) => j.id == 'j-pending').status, JobStatus.pending);
      await b.setCompanyStatus('c-pending', CompanyStatus.approved);
      expect((await b.jobs()).firstWhere((j) => j.id == 'j-pending').status, JobStatus.published);
      final log = await b.activity();
      expect(log.first.targetType, 'companies');
      expect(log.first.summary, contains('Waterloo Builders Ltd'));
    });

    test('viewers cannot moderate; moderators cannot suspend users', () async {
      final viewer = DemoAdminBackend(role: AdminRole.viewer);
      expect(() => viewer.setJobStatus('j1', JobStatus.closed), throwsA(isA<Exception>()));
      final mod = DemoAdminBackend(role: AdminRole.moderator);
      await mod.setJobStatus('j1', JobStatus.closed);
      expect(() => mod.setUserSuspended('u-2', true), throwsA(isA<Exception>()));
      expect(() => mod.saveSettings(const PlatformSettings(maintenanceEnabled: true)), throwsA(isA<Exception>()));
    });

    test('only owners manage the team, and the last owner is protected', () async {
      final admin = DemoAdminBackend(role: AdminRole.admin);
      expect(() => admin.addMember('mohamed.bangura@example.com', AdminRole.moderator), throwsA(isA<Exception>()));
      final owner = DemoAdminBackend();
      await owner.addMember('mohamed.bangura@example.com', AdminRole.moderator);
      expect((await owner.team()).length, 2);
      expect(() => owner.removeMember(owner.myUserId), throwsA(isA<Exception>()), reason: 'last owner');
      expect(() => owner.setMemberRole(owner.myUserId, AdminRole.admin), throwsA(isA<Exception>()), reason: 'last owner');
      await expectLater(owner.addMember('nobody@example.com', AdminRole.viewer), throwsA(isA<Exception>()));
    });

    test('admins cannot delete their own account from the users list', () async {
      final b = DemoAdminBackend();
      expect(() => b.deleteUser(b.myUserId), throwsA(isA<Exception>()));
      await b.deleteUser('u-2');
      expect((await b.users()).any((u) => u.id == 'u-2'), isFalse);
    });

    test('suspend and reinstate a user', () async {
      final b = DemoAdminBackend();
      await b.setUserSuspended('u-2', true, reason: 'Spam');
      var u = (await b.users()).firstWhere((u) => u.id == 'u-2');
      expect(u.suspended, isTrue);
      expect(u.suspendedReason, 'Spam');
      await b.setUserSuspended('u-2', false);
      u = (await b.users()).firstWhere((u) => u.id == 'u-2');
      expect(u.suspended, isFalse);
      expect(u.suspendedReason, isNull);
    });

    test('resolving a report closes it', () async {
      final b = DemoAdminBackend();
      expect((await b.reports()).single.status.isOpen, isTrue);
      await b.updateReport('r-1', ReportStatus.resolved, note: 'Job taken down');
      final r = (await b.reports()).single;
      expect(r.status, ReportStatus.resolved);
      expect(r.adminNote, 'Job taken down');
      expect(r.resolvedAt, isNotNull);
    });
  });

  group('stats', () {
    test('demo stats count the pending work', () async {
      final s = await DemoAdminBackend().stats();
      expect(s.companiesPending, 1);
      expect(s.jobsPending, 1);
      expect(s.reportsOpen, 1);
      expect(s.pendingWork, 3);
      expect(s.signups30d.length, 30);
      expect(s.topIndustries, isNotEmpty);
      expect(s.applicationsPerJob, greaterThan(0));
    });

    test('parses the admin_stats() JSON shape from the database', () {
      final s = AdminStats.fromJson({
        'users_total': 120,
        'seekers': 100,
        'employers': 20,
        'companies_pending': 3,
        'jobs_pending': 2,
        'reports_open': 1,
        'jobs_total': 50,
        'jobs_draft': 10,
        'applications_total': 200,
        'job_views': 4000,
        'companies_approved': 9,
        'companies_rejected': 1,
        'avg_response_days': 2.5,
        'avg_salary': 7250,
        'signups_30d': [
          {'day': '2026-10-01', 'count': 4},
          {'day': '2026-10-02', 'count': 0},
        ],
        'top_industries': [
          {'label': 'technology', 'count': 12},
        ],
        'by_status': {'applied': 150, 'hired': 5},
      });
      expect(s.pendingWork, 6);
      expect(s.applicationsPerJob, 5);
      expect(s.viewToApply, closeTo(0.05, 1e-9));
      expect(s.approvalRate, closeTo(0.9, 1e-9));
      expect(s.avgResponseDays, 2.5);
      expect(s.signups30d.first.count, 4);
      expect(s.topIndustries.single.label, 'technology');
      expect(s.byStatus['hired'], 5);
    });
  });

  group('models', () {
    test('platform settings round-trip through settings rows', () {
      const s = PlatformSettings(requireCompanyApproval: false, maintenanceEnabled: true, maintenanceMessage: 'Back soon', supportEmail: 'a@b.sl');
      final back = PlatformSettings.fromRows(s.toRows());
      expect(back.requireCompanyApproval, isFalse);
      expect(back.maintenanceEnabled, isTrue);
      expect(back.maintenanceMessage, 'Back soon');
      expect(back.supportEmail, 'a@b.sl');
    });

    test('announcements are live only inside their window', () {
      final now = DateTime(2026, 10, 7, 12);
      final a = Announcement(id: 'x', title: 't', startsAt: now.subtract(const Duration(days: 1)), endsAt: now.add(const Duration(days: 1)));
      expect(a.isLiveAt(now), isTrue);
      expect(a.isLiveAt(now.add(const Duration(days: 2))), isFalse);
      expect(Announcement(id: 'y', title: 't', active: false).isLiveAt(now), isFalse);
    });

    test('activity summaries are readable', () {
      final e = AuditEntry(
        id: '1',
        action: 'update',
        targetType: 'companies',
        createdAt: DateTime(2026),
        details: const {'status': 'approved', 'label': 'Acme'},
      );
      expect(e.summary, 'Updated company "Acme": status → approved');
    });
  });
}
