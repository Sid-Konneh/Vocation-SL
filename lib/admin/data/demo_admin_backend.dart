import '../../core/errors.dart';
import '../../data/demo/demo_companies.dart';
import '../../data/demo/demo_jobs.dart';
import '../../data/demo/demo_seed.dart';
import '../../models/models.dart';
import 'admin_backend.dart';

/// In-memory admin backend for demo mode and tests. Seeded from the demo
/// data; mirrors the database rules (role levels, last-owner protection,
/// activity log for every change). Resets when the app restarts.
class DemoAdminBackend implements AdminBackend {
  DemoAdminBackend({this.role = AdminRole.owner, String? myUserId, String? myEmail})
      : myUserId = myUserId ?? demoUserId,
        myEmail = myEmail ?? demoEmail {
    final now = DateTime.now();
    final pendingCompany = Company(
      id: 'c-pending',
      name: 'Waterloo Builders Ltd',
      industry: Industry.engineering,
      location: 'Waterloo',
      about: 'Construction firm registering to hire site staff.',
      size: '11–50 employees',
      founded: 2021,
      website: '',
      brandColor: 0xFF8A5A2B,
      status: CompanyStatus.pending,
      email: 'hr@waterloo-builders.example',
      phone: '+232 77 000 222',
      address: 'Main Motor Road, Waterloo',
    );
    _companies.addAll([
      for (final c in demoCompanies) AdminCompany(company: c, members: 1, jobCount: 0, createdAt: now.subtract(const Duration(days: 120))),
      AdminCompany(company: pendingCompany, members: 1, createdAt: now.subtract(const Duration(days: 1))),
    ]);
    final byId = {for (final c in [...demoCompanies, pendingCompany]) c.id: c};
    _jobs.addAll(buildDemoJobs(now).map((j) => j.withCompany(byId[j.companyId])));
    _jobs.add(Job(
      id: 'j-pending',
      title: 'Site Foreman',
      companyId: pendingCompany.id,
      location: 'Waterloo',
      employmentType: EmploymentType.contract,
      workMode: WorkMode.onsite,
      industry: Industry.engineering,
      experienceLevel: ExperienceLevel.mid,
      salaryMin: 5000,
      salaryMax: 7000,
      postedAt: now.subtract(const Duration(hours: 20)),
      deadline: now.add(const Duration(days: 20)),
      about: 'Lead a building crew.',
      description: 'Supervise daily site work for residential projects.',
      responsibilities: const ['Supervise crew'],
      requirements: const ['3 years site experience'],
      preferred: const [],
      skills: const ['Construction'],
      benefits: const [],
      status: JobStatus.pending,
      company: pendingCompany,
    ));
    final user = buildDemoUser(now);
    _users.addAll([
      AdminUser(id: user.id, email: user.email, name: user.fullName, role: 'seeker', createdAt: now.subtract(const Duration(days: 60)), lastSeenAt: now),
      AdminUser(id: 'u-2', email: 'mohamed.bangura@example.com', name: 'Mohamed Bangura', role: 'seeker', createdAt: now.subtract(const Duration(days: 3))),
      AdminUser(id: 'u-3', email: 'hr@waterloo-builders.example', name: 'Isatu Conteh', role: 'employer', createdAt: now.subtract(const Duration(days: 1))),
    ]);
    _apps.addAll(buildDemoApplications(now, user).map((a) => a.copyWith(job: () => _jobs.where((j) => j.id == a.jobId).firstOrNull)));
    _reports.add(Report(
      id: 'r-1',
      targetType: ReportTarget.job,
      targetId: 'j-pending',
      targetLabel: 'Site Foreman',
      reason: 'Asks for payment or fees',
      details: 'They asked me to pay SLE 200 for a uniform before the interview.',
      status: ReportStatus.open,
      reporterId: 'u-2',
      createdAt: now.subtract(const Duration(hours: 5)),
    ));
    _team.add(AdminMember(userId: this.myUserId, role: role, createdAt: now.subtract(const Duration(days: 30)), email: this.myEmail, name: user.fullName));
    _pages.addAll(const [
      SitePage(slug: 'help', title: 'Help & FAQs'),
      SitePage(slug: 'privacy', title: 'Privacy Policy'),
      SitePage(slug: 'terms', title: 'Terms of Use'),
    ]);
  }

  AdminRole role;
  final String myUserId;
  final String myEmail;

  final _companies = <AdminCompany>[];
  final _jobs = <Job>[];
  final _users = <AdminUser>[];
  final _apps = <JobApplication>[];
  final _reports = <Report>[];
  final _announcements = <Announcement>[];
  final _pages = <SitePage>[];
  final _team = <AdminMember>[];
  final log = <AuditEntry>[];
  PlatformSettings _settings = const PlatformSettings();
  var _seq = 0;

  void _need(AdminRole r) {
    if (!role.can(r)) throw AuthException('Your admin role (${role.label}) can\'t do that.');
  }

  void _log(String action, String type, String id, String label, [Map<String, dynamic> details = const {}]) {
    log.insert(0, AuditEntry(
      id: '${++_seq}',
      actorEmail: myEmail,
      action: action,
      targetType: type,
      targetId: id,
      details: {...details, 'label': label},
      createdAt: DateTime.now(),
    ));
  }

  Job _jobWith(Job j, {JobStatus? status, bool? featured}) => Job(
        id: j.id,
        title: j.title,
        companyId: j.companyId,
        location: j.location,
        employmentType: j.employmentType,
        workMode: j.workMode,
        industry: j.industry,
        experienceLevel: j.experienceLevel,
        salaryMin: j.salaryMin,
        salaryMax: j.salaryMax,
        postedAt: j.postedAt,
        deadline: j.deadline,
        about: j.about,
        description: j.description,
        responsibilities: j.responsibilities,
        requirements: j.requirements,
        preferred: j.preferred,
        skills: j.skills,
        benefits: j.benefits,
        applicants: j.applicants,
        featured: featured ?? j.featured,
        company: j.company,
        status: status ?? j.status,
        views: j.views,
      );

  Company _companyWith(Company c, {CompanyStatus? status, bool? verified}) => Company(
        id: c.id,
        name: c.name,
        industry: c.industry,
        location: c.location,
        about: c.about,
        size: c.size,
        founded: c.founded,
        website: c.website,
        brandColor: c.brandColor,
        verified: verified ?? c.verified,
        status: status ?? c.status,
        email: c.email,
        phone: c.phone,
        address: c.address,
        ownerId: c.ownerId,
        logoUrl: c.logoUrl,
      );

  @override
  Future<AdminRole?> myRole() async => _team.where((m) => m.userId == myUserId).firstOrNull?.role;

  @override
  Future<AdminStats> stats() async {
    final now = DateTime.now();
    List<({DateTime day, int count})> series(Iterable<DateTime> dates) {
      final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 29));
      final counts = List<int>.filled(30, 0);
      for (final d in dates) {
        final i = DateTime(d.year, d.month, d.day).difference(start).inDays;
        if (i >= 0 && i < 30) counts[i]++;
      }
      return [for (var i = 0; i < 30; i++) (day: start.add(Duration(days: i)), count: counts[i])];
    }

    List<CountPoint> top(Iterable<String> keys) {
      final m = <String, int>{};
      for (final k in keys) {
        m[k] = (m[k] ?? 0) + 1;
      }
      final l = m.entries.map((e) => CountPoint(e.key, e.value)).toList()..sort((a, b) => b.count.compareTo(a.count));
      return l.take(8).toList();
    }

    final live = _jobs.where((j) => j.status == JobStatus.published);
    return AdminStats(
      usersTotal: _users.length,
      seekers: _users.where((u) => u.role != 'employer').length,
      employers: _users.where((u) => u.role == 'employer').length,
      suspended: _users.where((u) => u.suspended).length,
      newUsers7d: _users.where((u) => now.difference(u.createdAt).inDays < 7).length,
      companiesTotal: _companies.length,
      companiesPending: _companies.where((c) => c.company.status == CompanyStatus.pending).length,
      jobsTotal: _jobs.length,
      jobsLive: live.where((j) => !j.isClosed).length,
      jobsPending: _jobs.where((j) => j.status == JobStatus.pending).length,
      applicationsTotal: _apps.length,
      applications7d: _apps.where((a) => now.difference(a.submittedAt).inDays < 7).length,
      hires: _apps.where((a) => a.status == ApplicationStatus.hired).length,
      reportsOpen: _reports.where((r) => r.status.isOpen).length,
      jobViews: _jobs.fold(0, (s, j) => s + j.views),
      signups30d: series(_users.map((u) => u.createdAt)),
      applications30d: series(_apps.map((a) => a.submittedAt)),
      jobs30d: series(_jobs.map((j) => j.postedAt)),
      byStatus: {for (final s in ApplicationStatus.values) s.name: _apps.where((a) => a.status == s).length},
      topIndustries: top(live.map((j) => j.industry.label)),
      topLocations: top(live.map((j) => j.location)),
      topCompanies: top(_apps.map((a) => a.job?.companyName ?? '')),
    );
  }

  @override
  Future<List<Job>> jobs() async => List.of(_jobs);

  @override
  Future<void> setJobStatus(String jobId, JobStatus status) async {
    _need(AdminRole.moderator);
    final i = _jobs.indexWhere((j) => j.id == jobId);
    _jobs[i] = _jobWith(_jobs[i], status: status);
    _log('update', 'jobs', jobId, _jobs[i].title, {'status': status.name});
  }

  @override
  Future<void> setJobFeatured(String jobId, bool featured) async {
    _need(AdminRole.moderator);
    final i = _jobs.indexWhere((j) => j.id == jobId);
    _jobs[i] = _jobWith(_jobs[i], featured: featured);
    _log('update', 'jobs', jobId, _jobs[i].title, {'featured': featured});
  }

  @override
  Future<void> deleteJob(String jobId) async {
    _need(AdminRole.moderator);
    final j = _jobs.firstWhere((j) => j.id == jobId);
    _jobs.remove(j);
    _log('delete', 'jobs', jobId, j.title);
  }

  @override
  Future<List<AdminCompany>> companies() async => [
        for (final c in _companies)
          AdminCompany(company: c.company, members: c.members, createdAt: c.createdAt, jobCount: _jobs.where((j) => j.companyId == c.company.id).length),
      ];

  @override
  Future<void> setCompanyStatus(String companyId, CompanyStatus status) async {
    _need(AdminRole.moderator);
    final i = _companies.indexWhere((c) => c.company.id == companyId);
    final c = _companies[i];
    _companies[i] = AdminCompany(company: _companyWith(c.company, status: status), members: c.members, createdAt: c.createdAt);
    // Approval publishes the company's waiting jobs (as the database does).
    if (status == CompanyStatus.approved) {
      for (var k = 0; k < _jobs.length; k++) {
        if (_jobs[k].companyId == companyId && _jobs[k].status == JobStatus.pending) _jobs[k] = _jobWith(_jobs[k], status: JobStatus.published);
      }
    }
    _log('update', 'companies', companyId, c.company.name, {'status': status.name});
  }

  @override
  Future<void> setCompanyVerified(String companyId, bool verified) async {
    _need(AdminRole.moderator);
    final i = _companies.indexWhere((c) => c.company.id == companyId);
    final c = _companies[i];
    _companies[i] = AdminCompany(company: _companyWith(c.company, verified: verified), members: c.members, createdAt: c.createdAt);
    _log('update', 'companies', companyId, c.company.name, {'verified': verified});
  }

  @override
  Future<List<AdminUser>> users() async => List.of(_users);

  @override
  Future<void> setUserSuspended(String userId, bool suspended, {String? reason}) async {
    _need(AdminRole.admin);
    final i = _users.indexWhere((u) => u.id == userId);
    _users[i] = _users[i].copyWith(suspended: suspended, suspendedReason: () => suspended ? reason : null);
    _log('update', 'profiles', userId, _users[i].name, {'suspended': suspended});
  }

  @override
  Future<void> deleteUser(String userId) async {
    _need(AdminRole.admin);
    if (userId == myUserId) throw const ValidationException('Use Delete account to remove your own account.');
    final u = _users.firstWhere((u) => u.id == userId);
    _users.remove(u);
    _apps.removeWhere((a) => a.userId == userId);
    _log('delete', 'users', userId, u.email);
  }

  @override
  Future<List<JobApplication>> applications() async => List.of(_apps);

  @override
  Future<List<Report>> reports() async => List.of(_reports);

  @override
  Future<void> updateReport(String reportId, ReportStatus status, {String note = ''}) async {
    _need(AdminRole.moderator);
    final i = _reports.indexWhere((r) => r.id == reportId);
    _reports[i] = _reports[i].copyWith(status: status, adminNote: note);
    _log('update', 'reports', reportId, _reports[i].targetLabel, {'status': status.name});
  }

  @override
  Future<List<Announcement>> announcements() async => List.of(_announcements);

  @override
  Future<void> saveAnnouncement(Announcement a) async {
    _need(AdminRole.admin);
    final saved = a.id.isEmpty
        ? Announcement(
            id: 'a-${++_seq}',
            title: a.title,
            body: a.body,
            audience: a.audience,
            level: a.level,
            active: a.active,
            startsAt: a.startsAt,
            endsAt: a.endsAt,
            createdAt: DateTime.now(),
          )
        : a;
    _announcements.removeWhere((x) => x.id == saved.id);
    _announcements.insert(0, saved);
    _log(a.id.isEmpty ? 'insert' : 'update', 'announcements', saved.id, saved.title);
  }

  @override
  Future<void> deleteAnnouncement(String id) async {
    _need(AdminRole.admin);
    final a = _announcements.firstWhere((x) => x.id == id);
    _announcements.remove(a);
    _log('delete', 'announcements', id, a.title);
  }

  @override
  Future<List<SitePage>> pages() async => List.of(_pages);

  @override
  Future<void> savePage(String slug, String title, String body) async {
    _need(AdminRole.admin);
    _pages.removeWhere((p) => p.slug == slug);
    _pages.add(SitePage(slug: slug, title: title, body: body, updatedAt: DateTime.now()));
    _pages.sort((a, b) => a.slug.compareTo(b.slug));
    _log('update', 'site_pages', slug, title);
  }

  @override
  Future<PlatformSettings> settings() async => _settings;

  @override
  Future<void> saveSettings(PlatformSettings s) async {
    _need(AdminRole.admin);
    _settings = s;
    _log('update', 'platform_settings', 'settings', 'Platform settings', {
      'require_company_approval': s.requireCompanyApproval,
      'maintenance': s.maintenanceEnabled,
    });
  }

  @override
  Future<List<AdminMember>> team() async => List.of(_team);

  @override
  Future<void> addMember(String email, AdminRole role) async {
    _need(AdminRole.owner);
    final u = _users.where((u) => u.email.toLowerCase() == email.trim().toLowerCase()).firstOrNull;
    if (u == null) throw const ValidationException('No account uses that email. Ask them to sign up first.');
    _team.removeWhere((m) => m.userId == u.id);
    _team.add(AdminMember(userId: u.id, role: role, createdAt: DateTime.now(), email: u.email, name: u.name));
    _log('insert', 'admins', u.id, u.email, {'role': role.name});
  }

  void _keepOwner(String changingUserId) {
    final otherOwners = _team.where((m) => m.role == AdminRole.owner && m.userId != changingUserId);
    final isOwner = _team.any((m) => m.userId == changingUserId && m.role == AdminRole.owner);
    if (isOwner && otherOwners.isEmpty) throw const ValidationException('There must always be at least one owner.');
  }

  @override
  Future<void> setMemberRole(String userId, AdminRole role) async {
    _need(AdminRole.owner);
    if (role != AdminRole.owner) _keepOwner(userId);
    final i = _team.indexWhere((m) => m.userId == userId);
    final m = _team[i];
    _team[i] = AdminMember(userId: m.userId, role: role, createdAt: m.createdAt, email: m.email, name: m.name);
    if (userId == myUserId) this.role = role;
    _log('update', 'admins', userId, m.email, {'role': role.name});
  }

  @override
  Future<void> removeMember(String userId) async {
    _need(AdminRole.owner);
    _keepOwner(userId);
    final m = _team.firstWhere((m) => m.userId == userId);
    _team.remove(m);
    _log('delete', 'admins', userId, m.email);
  }

  @override
  Future<List<AuditEntry>> activity({int limit = 300}) async => log.take(limit).toList();
}
