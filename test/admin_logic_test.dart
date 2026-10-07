import 'package:flutter_test/flutter_test.dart';
import 'package:vocation_sl/admin/data/demo_admin_backend.dart';
import 'package:vocation_sl/models/models.dart';

void main() {
  group('permissions', () {
    test('approving a company gives the check mark but its jobs still need review', () async {
      final b = DemoAdminBackend();
      await b.setCompanyStatus('c-pending', CompanyStatus.approved);
      final c = (await b.companies()).firstWhere((c) => c.company.id == 'c-pending').company;
      expect(c.verified, isTrue);
      expect((await b.jobs()).firstWhere((j) => j.id == 'j-pending').status, JobStatus.pending);
      final log = await b.activity();
      expect(log.first.targetType, 'companies');
      expect(log.first.summary, contains('Waterloo Builders Ltd'));

      await b.setCompanyStatus('c-pending', CompanyStatus.suspended);
      expect((await b.companies()).firstWhere((c) => c.company.id == 'c-pending').company.verified, isFalse);
    });

    test('with job review off, approving a company publishes its waiting jobs', () async {
      final b = DemoAdminBackend();
      await b.saveSettings(const PlatformSettings(requireJobApproval: false));
      await b.setCompanyStatus('c-pending', CompanyStatus.approved);
      expect((await b.jobs()).firstWhere((j) => j.id == 'j-pending').status, JobStatus.published);
    });

    test('approve, decline and reject jobs; approval creates a draft invoice', () async {
      final b = DemoAdminBackend();
      final before = (await b.invoices()).length;
      await b.setJobStatus('j-pending', JobStatus.declined, note: 'Add the salary');
      var j = (await b.jobs()).firstWhere((j) => j.id == 'j-pending');
      expect(j.status, JobStatus.declined);
      expect(j.reviewNote, 'Add the salary');
      expect((await b.invoices()).length, before, reason: 'no invoice until live');

      await b.setJobStatus('j-pending', JobStatus.published);
      j = (await b.jobs()).firstWhere((j) => j.id == 'j-pending');
      expect(j.reviewNote, isEmpty);
      final inv = (await b.invoices()).first;
      expect(inv.jobId, 'j-pending');
      expect(inv.needsPricing, isTrue);
      expect(inv.billToName, 'Waterloo Builders Ltd');

      // Closing and reopening doesn't create a second invoice.
      await b.setJobStatus('j-pending', JobStatus.closed);
      await b.setJobStatus('j-pending', JobStatus.published);
      expect((await b.invoices()).where((i) => i.jobId == 'j-pending').length, 1);
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

  group('invoices', () {
    test('totals apply tax after the discount and round to cents', () {
      final i = Invoice(id: '1', number: 'VSL-1', createdAt: DateTime(2026), quantity: 2, unitPrice: 250.5, discount: 1, taxRate: 15);
      expect(i.subtotal, 501);
      expect(i.taxAmount, 75);
      expect(i.total, 575);
      expect(Invoice(id: '2', number: 'x', createdAt: DateTime(2026), unitPrice: 10, discount: 50).total, 0);
    });

    test('issue fills dates, paid records payment, only admins can edit', () async {
      final b = DemoAdminBackend();
      final draft = (await b.invoices()).firstWhere((i) => i.status == InvoiceStatus.draft);
      await b.saveInvoice(draft.copyWith(unitPrice: 400, status: InvoiceStatus.issued));
      var i = (await b.invoices()).firstWhere((x) => x.id == draft.id);
      expect(i.issueDate, isNotNull);
      expect(i.dueDate!.difference(i.issueDate!).inDays, 14);
      expect(i.total, 460);

      await b.saveInvoice(i.copyWith(status: InvoiceStatus.paid, paymentMethod: 'Orange Money'));
      i = (await b.invoices()).firstWhere((x) => x.id == draft.id);
      expect(i.paidAt, isNotNull);
      expect((await b.activity()).first.summary, contains(i.number));

      final mod = DemoAdminBackend(role: AdminRole.moderator);
      final other = (await mod.invoices()).first;
      expect(() => mod.saveInvoice(other.copyWith(unitPrice: 1)), throwsA(isA<Exception>()));
    });

    test('overdue means issued and past the due date', () {
      final i = Invoice(id: '1', number: 'x', createdAt: DateTime(2026), status: InvoiceStatus.issued, dueDate: DateTime(2026, 10, 1));
      expect(i.isOverdueAt(DateTime(2026, 10, 2)), isTrue);
      expect(i.isOverdueAt(DateTime(2026, 10, 1, 18)), isFalse);
      expect(i.copyWith(status: InvoiceStatus.paid).isOverdueAt(DateTime(2026, 11)), isFalse);
    });

    test('database rows parse', () {
      final i = Invoice.fromJson({
        'id': 'a',
        'number': 'VSL-2026-00001',
        'status': 'void',
        'unit_price': '1200.50',
        'quantity': 1,
        'tax_rate': 15,
        'issue_date': '2026-10-01',
        'created_at': '2026-10-01T10:00:00Z',
      }..['unit_price'] = 1200.5);
      expect(i.status, InvoiceStatus.voided);
      expect(i.toJson()['status'], 'void');
      expect(i.toJson()['issue_date'], '2026-10-01');
    });
  });

  group('users', () {
    test('sign-in details are admin-only and the view is logged', () async {
      final b = DemoAdminBackend();
      final me = (await b.users()).first;
      final info = await b.userLogin(me.id);
      expect(info!.providers, isNotEmpty);
      expect((await b.activity()).first.summary, startsWith('Viewed user'));
      expect(() => DemoAdminBackend(role: AdminRole.moderator).userLogin(me.id), throwsA(isA<Exception>()));
      expect(me.profile?.skills, isNotEmpty);
    });

    test('device names are readable', () {
      expect(describeUserAgent('Mozilla/5.0 (Linux; Android 13) Chrome/126.0 Mobile Safari/537.36'), 'Chrome on Android');
      expect(describeUserAgent('Dart/3.4 (dart:io)'), 'Vocation SL app');
      expect(describeUserAgent(''), 'Unknown device');
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
