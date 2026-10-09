/// Models for the admin dashboard and the public bits it controls
/// (reports, announcements, pages, platform settings).
library;

import 'company.dart';
import 'job.dart';
import 'user.dart';

enum AdminRole {
  viewer('Viewer', 1, 'Can view everything, change nothing'),
  moderator('Moderator', 2, 'Moderates jobs, employers and reports'),
  admin('Admin', 3, 'Everything except managing the admin team'),
  owner('Owner', 4, 'Full control, including the admin team');

  const AdminRole(this.label, this.level, this.description);
  final String label;
  final int level;
  final String description;

  static AdminRole? fromName(Object? n) => AdminRole.values.where((r) => r.name == n).firstOrNull;
  bool can(AdminRole needed) => level >= needed.level;
}

class AdminMember {
  const AdminMember({required this.userId, required this.role, required this.createdAt, this.email = '', this.name = ''});
  final String userId;
  final AdminRole role;
  final DateTime createdAt;
  final String email;
  final String name;

  factory AdminMember.fromJson(Map<String, dynamic> j) {
    final p = j['profile'] is Map ? Map<String, dynamic>.from(j['profile'] as Map) : const <String, dynamic>{};
    return AdminMember(
      userId: j['user_id'] as String,
      role: AdminRole.fromName(j['role']) ?? AdminRole.viewer,
      createdAt: DateTime.parse(j['created_at'] as String),
      email: (p['email'] ?? j['email'] ?? '') as String,
      name: (p['full_name'] ?? j['name'] ?? '') as String,
    );
  }
}

/// A user account as admins see it.
class AdminUser {
  const AdminUser({
    required this.id,
    required this.email,
    required this.name,
    required this.createdAt,
    this.role,
    this.lastSeenAt,
    this.suspended = false,
    this.suspendedReason,
    this.headline = '',
    this.location = '',
    this.phone = '',
    this.profileData = const {},
  });

  final String id;
  final String email;
  final String name;

  /// The profile the user filled in (CV, experience, skills, preferences).
  final Map<String, dynamic> profileData;

  /// The profile photo the user uploaded (base64), if any.
  String? get photoBase64 {
    final p = profileData['photo_base64'];
    return p is String && p.isNotEmpty ? p : null;
  }

  /// The parsed profile, or null if the stored data can't be read.
  AppUser? get profile {
    try {
      return AppUser.fromJson({...profileData, 'id': id, 'email': email, 'full_name': name});
    } catch (_) {
      return null;
    }
  }

  final String? role;
  final DateTime createdAt;
  final DateTime? lastSeenAt;
  final bool suspended;
  final String? suspendedReason;
  final String headline;
  final String location;
  final String phone;

  String get roleLabel => switch (role) { 'employer' => 'Employer', 'seeker' => 'Job seeker', _ => 'Not chosen' };

  AdminUser copyWith({bool? suspended, String? Function()? suspendedReason}) => AdminUser(
        id: id,
        email: email,
        name: name,
        role: role,
        createdAt: createdAt,
        lastSeenAt: lastSeenAt,
        suspended: suspended ?? this.suspended,
        suspendedReason: suspendedReason != null ? suspendedReason() : this.suspendedReason,
        headline: headline,
        location: location,
        phone: phone,
        profileData: profileData,
      );

  factory AdminUser.fromJson(Map<String, dynamic> j) {
    final data = j['data'] is Map ? Map<String, dynamic>.from(j['data'] as Map) : const <String, dynamic>{};
    return AdminUser(
      id: j['id'] as String,
      email: (j['email'] ?? data['email'] ?? '') as String,
      name: (j['full_name'] ?? data['full_name'] ?? '') as String,
      role: j['role'] as String?,
      createdAt: DateTime.tryParse('${j['created_at']}') ?? DateTime.now(),
      lastSeenAt: j['last_seen_at'] == null ? null : DateTime.tryParse('${j['last_seen_at']}'),
      suspended: j['suspended'] as bool? ?? false,
      suspendedReason: j['suspended_reason'] as String?,
      headline: data['headline'] as String? ?? '',
      location: data['location'] as String? ?? '',
      phone: data['phone'] as String? ?? '',
      profileData: data,
    );
  }
}

/// How and when a user signs in, read from the auth system (admins only).
class UserLoginInfo {
  const UserLoginInfo({
    this.email = '',
    this.phone = '',
    this.providers = const [],
    this.createdAt,
    this.lastSignInAt,
    this.emailConfirmedAt,
    this.bannedUntil,
    this.identities = const [],
    this.sessions = const [],
    this.companies = const [],
    this.adminRole,
    this.applications = 0,
  });

  final String email;
  final String phone;

  /// e.g. ['email', 'google'].
  final List<String> providers;
  final DateTime? createdAt;
  final DateTime? lastSignInAt;
  final DateTime? emailConfirmedAt;
  final DateTime? bannedUntil;
  final List<({String provider, String email, DateTime? createdAt, DateTime? lastSignInAt})> identities;

  /// Most recent first.
  final List<({DateTime? createdAt, DateTime? lastActiveAt, String userAgent, String ip})> sessions;
  final List<({String id, String name, String role, String status})> companies;
  final AdminRole? adminRole;
  final int applications;

  static String providerLabel(String p) => switch (p) { 'email' => 'Email and password', 'google' => 'Google', _ => p };

  factory UserLoginInfo.fromJson(Map<String, dynamic> j) {
    DateTime? d(Object? v) => v == null ? null : DateTime.tryParse('$v');
    List<Map<String, dynamic>> maps(Object? v) => [for (final e in (v as List? ?? const [])) Map<String, dynamic>.from(e as Map)];
    return UserLoginInfo(
      email: j['email'] as String? ?? '',
      phone: j['phone'] as String? ?? '',
      providers: [for (final p in (j['providers'] as List? ?? const [])) if (p != null) '$p'],
      createdAt: d(j['created_at']),
      lastSignInAt: d(j['last_sign_in_at']),
      emailConfirmedAt: d(j['email_confirmed_at']),
      bannedUntil: d(j['banned_until']),
      identities: [
        for (final i in maps(j['identities']))
          (provider: '${i['provider'] ?? ''}', email: '${i['email'] ?? ''}', createdAt: d(i['created_at']), lastSignInAt: d(i['last_sign_in_at'])),
      ],
      sessions: [
        for (final s in maps(j['sessions']))
          (createdAt: d(s['created_at']), lastActiveAt: d(s['updated_at']), userAgent: '${s['user_agent'] ?? ''}', ip: '${s['ip'] ?? ''}'),
      ],
      companies: [
        for (final c in maps(j['companies'])) (id: '${c['id']}', name: '${c['name'] ?? ''}', role: '${c['role'] ?? ''}', status: '${c['status'] ?? ''}'),
      ],
      adminRole: AdminRole.fromName(j['admin_role'] as String?),
      applications: (j['applications'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A short, readable device name from a browser user-agent string.
String describeUserAgent(String ua) {
  if (ua.isEmpty) return 'Unknown device';
  final os = ua.contains('Android')
      ? 'Android'
      : ua.contains('iPhone') || ua.contains('iPad')
          ? 'iOS'
          : ua.contains('Windows')
              ? 'Windows'
              : ua.contains('Mac OS')
                  ? 'Mac'
                  : ua.contains('Linux')
                      ? 'Linux'
                      : null;
  final app = ua.contains('Dart/')
      ? 'Vocation SL app'
      : ua.contains('Edg/')
          ? 'Edge'
          : ua.contains('Chrome/')
              ? 'Chrome'
              : ua.contains('Firefox/')
                  ? 'Firefox'
                  : ua.contains('Safari/')
                      ? 'Safari'
                      : null;
  if (os == null && app == null) return ua.length > 60 ? '${ua.substring(0, 60)}…' : ua;
  return [app, os].whereType<String>().join(' on ');
}

/// A company as admins see it (with team size).
class AdminCompany {
  const AdminCompany({required this.company, required this.members, required this.createdAt, this.jobCount = 0});
  final Company company;
  final int members;
  final int jobCount;
  final DateTime createdAt;

  factory AdminCompany.fromJson(Map<String, dynamic> j) {
    int count(Object? v) => v is List && v.isNotEmpty ? ((v.first as Map)['count'] as num?)?.toInt() ?? 0 : 0;
    return AdminCompany(
      company: Company.fromJson(j),
      members: count(j['members']),
      jobCount: count(j['jobs']),
      createdAt: DateTime.tryParse('${j['created_at']}') ?? DateTime.now(),
    );
  }
}

enum ReportStatus {
  open('Open'),
  reviewing('Reviewing'),
  resolved('Resolved'),
  dismissed('Dismissed');

  const ReportStatus(this.label);
  final String label;
  bool get isOpen => this == open || this == reviewing;
}

enum ReportTarget {
  job('Job'),
  company('Company'),
  user('User');

  const ReportTarget(this.label);
  final String label;
}

const reportReasons = [
  'Fake or misleading job',
  'Asks for payment or fees',
  'Scam or fraud',
  'Discriminatory content',
  'Offensive or inappropriate',
  'Job no longer available',
  'Other',
];

class Report {
  const Report({
    required this.id,
    required this.targetType,
    required this.targetId,
    required this.reason,
    required this.status,
    required this.createdAt,
    this.targetLabel = '',
    this.details = '',
    this.adminNote = '',
    this.reporterId,
    this.resolvedAt,
  });

  final String id;
  final ReportTarget targetType;
  final String targetId;
  final String targetLabel;
  final String reason;
  final String details;
  final ReportStatus status;
  final String adminNote;
  final String? reporterId;
  final DateTime createdAt;
  final DateTime? resolvedAt;

  Report copyWith({ReportStatus? status, String? adminNote}) => Report(
        id: id,
        targetType: targetType,
        targetId: targetId,
        targetLabel: targetLabel,
        reason: reason,
        details: details,
        status: status ?? this.status,
        adminNote: adminNote ?? this.adminNote,
        reporterId: reporterId,
        createdAt: createdAt,
        resolvedAt: (status != null && !status.isOpen) ? DateTime.now() : resolvedAt,
      );

  factory Report.fromJson(Map<String, dynamic> j) => Report(
        id: j['id'] as String,
        targetType: ReportTarget.values.where((t) => t.name == j['target_type']).firstOrNull ?? ReportTarget.job,
        targetId: '${j['target_id']}',
        targetLabel: j['target_label'] as String? ?? '',
        reason: j['reason'] as String? ?? '',
        details: j['details'] as String? ?? '',
        status: ReportStatus.values.where((s) => s.name == j['status']).firstOrNull ?? ReportStatus.open,
        adminNote: j['admin_note'] as String? ?? '',
        reporterId: j['reporter_id'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
        resolvedAt: j['resolved_at'] == null ? null : DateTime.tryParse('${j['resolved_at']}'),
      );
}

enum AnnouncementAudience {
  all('Everyone'),
  seeker('Job seekers'),
  employer('Employers');

  const AnnouncementAudience(this.label);
  final String label;
}

enum AnnouncementLevel {
  info('Information'),
  warning('Warning'),
  success('Good news');

  const AnnouncementLevel(this.label);
  final String label;
}

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    this.body = '',
    this.audience = AnnouncementAudience.all,
    this.level = AnnouncementLevel.info,
    this.active = true,
    this.startsAt,
    this.endsAt,
    this.createdAt,
  });

  final String id;
  final String title;
  final String body;
  final AnnouncementAudience audience;
  final AnnouncementLevel level;
  final bool active;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? createdAt;

  bool isLiveAt(DateTime now) =>
      active && (startsAt == null || !startsAt!.isAfter(now)) && (endsAt == null || endsAt!.isAfter(now));

  factory Announcement.fromJson(Map<String, dynamic> j) => Announcement(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        audience: AnnouncementAudience.values.where((a) => a.name == j['audience']).firstOrNull ?? AnnouncementAudience.all,
        level: AnnouncementLevel.values.where((a) => a.name == j['level']).firstOrNull ?? AnnouncementLevel.info,
        active: j['active'] as bool? ?? true,
        startsAt: j['starts_at'] == null ? null : DateTime.tryParse('${j['starts_at']}'),
        endsAt: j['ends_at'] == null ? null : DateTime.tryParse('${j['ends_at']}'),
        createdAt: j['created_at'] == null ? null : DateTime.tryParse('${j['created_at']}'),
      );

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'title': title,
        'body': body,
        'audience': audience.name,
        'level': level.name,
        'active': active,
        'starts_at': startsAt?.toUtc().toIso8601String(),
        'ends_at': endsAt?.toUtc().toIso8601String(),
      };
}

class SitePage {
  const SitePage({required this.slug, required this.title, this.body = '', this.updatedAt});
  final String slug;
  final String title;
  final String body;
  final DateTime? updatedAt;

  factory SitePage.fromJson(Map<String, dynamic> j) => SitePage(
        slug: j['slug'] as String,
        title: j['title'] as String? ?? '',
        body: j['body'] as String? ?? '',
        updatedAt: j['updated_at'] == null ? null : DateTime.tryParse('${j['updated_at']}'),
      );
}

class PlatformSettings {
  const PlatformSettings({
    this.requireCompanyApproval = true,
    this.requireJobApproval = true,
    this.maintenanceEnabled = false,
    this.maintenanceMessage = '',
    this.supportEmail = 'vocationxsl@gmail.com',
  });

  final bool requireCompanyApproval;

  /// Every new or resubmitted job waits for an admin before going live.
  final bool requireJobApproval;
  final bool maintenanceEnabled;
  final String maintenanceMessage;
  final String supportEmail;

  PlatformSettings copyWith({bool? requireCompanyApproval, bool? requireJobApproval, bool? maintenanceEnabled, String? maintenanceMessage, String? supportEmail}) =>
      PlatformSettings(
        requireCompanyApproval: requireCompanyApproval ?? this.requireCompanyApproval,
        requireJobApproval: requireJobApproval ?? this.requireJobApproval,
        maintenanceEnabled: maintenanceEnabled ?? this.maintenanceEnabled,
        maintenanceMessage: maintenanceMessage ?? this.maintenanceMessage,
        supportEmail: supportEmail ?? this.supportEmail,
      );

  /// From platform_settings rows ({key, value}).
  factory PlatformSettings.fromRows(List<Map<String, dynamic>> rows) {
    final m = {for (final r in rows) r['key'] as String: r['value']};
    final maint = m['maintenance'] is Map ? Map<String, dynamic>.from(m['maintenance'] as Map) : const <String, dynamic>{};
    return PlatformSettings(
      requireCompanyApproval: m['require_company_approval'] as bool? ?? true,
      requireJobApproval: m['require_job_approval'] as bool? ?? true,
      maintenanceEnabled: maint['enabled'] as bool? ?? false,
      maintenanceMessage: maint['message'] as String? ?? '',
      supportEmail: m['support_email'] as String? ?? 'vocationxsl@gmail.com',
    );
  }

  List<Map<String, dynamic>> toRows() => [
        {'key': 'require_company_approval', 'value': requireCompanyApproval},
        {'key': 'require_job_approval', 'value': requireJobApproval},
        {'key': 'maintenance', 'value': {'enabled': maintenanceEnabled, 'message': maintenanceMessage}},
        {'key': 'support_email', 'value': supportEmail},
      ];
}

class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.action,
    required this.targetType,
    required this.createdAt,
    this.actorEmail = '',
    this.targetId,
    this.details = const {},
  });

  final String id;
  final String actorEmail;
  final String action;
  final String targetType;
  final String? targetId;
  final Map<String, dynamic> details;
  final DateTime createdAt;

  String get label => details['label'] as String? ?? '';

  /// A short human-readable description of the change.
  String get summary {
    final what = switch (targetType) {
      'companies' => 'company',
      'jobs' => 'job',
      'profiles' => 'user',
      'users' => 'user',
      'reports' => 'report',
      'announcements' => 'announcement',
      'site_pages' => 'page',
      'platform_settings' => 'setting',
      'admins' => 'admin team member',
      'invoices' => 'invoice',
      _ => targetType,
    };
    final changes = details.entries.where((e) => e.key != 'label' && e.key != 'id').map((e) => '${e.key} → ${e.value}').take(3).join(', ');
    if (action == 'view') return 'Viewed $what${label.isEmpty ? '' : ' "$label"'} ${details['viewed'] ?? ''}'.trimRight();
    final verb = switch (action) { 'insert' => 'Created', 'delete' => 'Deleted', _ => 'Updated' };
    return '$verb $what${label.isEmpty ? '' : ' "$label"'}${action == 'update' && changes.isNotEmpty ? ': $changes' : ''}';
  }

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
        id: '${j['id']}',
        actorEmail: j['actor_email'] as String? ?? '',
        action: j['action'] as String? ?? '',
        targetType: j['target_type'] as String? ?? '',
        targetId: j['target_id'] as String?,
        details: j['details'] is Map ? Map<String, dynamic>.from(j['details'] as Map) : const {},
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

class CountPoint {
  const CountPoint(this.label, this.count);
  final String label;
  final int count;
}

class AdminStats {
  const AdminStats({
    this.usersTotal = 0,
    this.seekers = 0,
    this.employers = 0,
    this.suspended = 0,
    this.newUsers7d = 0,
    this.companiesTotal = 0,
    this.companiesPending = 0,
    this.jobsTotal = 0,
    this.jobsLive = 0,
    this.jobsPending = 0,
    this.applicationsTotal = 0,
    this.applications7d = 0,
    this.hires = 0,
    this.reportsOpen = 0,
    this.jobViews = 0,
    this.signups30d = const [],
    this.applications30d = const [],
    this.jobs30d = const [],
    this.byStatus = const {},
    this.topIndustries = const [],
    this.topLocations = const [],
    this.topCompanies = const [],
    this.activeUsers7d = 0,
    this.companiesApproved = 0,
    this.companiesRejected = 0,
    this.companiesSuspended = 0,
    this.companiesVerified = 0,
    this.jobsDraft = 0,
    this.jobsClosed = 0,
    this.jobsClosing7d = 0,
    this.jobsFeatured = 0,
    this.avgSalary = 0,
    this.hires30d = 0,
    this.reportsTotal = 0,
    this.avgResponseDays,
    this.byEmploymentType = const [],
    this.byWorkMode = const [],
    this.byExperience = const [],
    this.seekerLocations = const [],
    this.reportsByReason = const [],
  });

  final int usersTotal, seekers, employers, suspended, newUsers7d;
  final int companiesTotal, companiesPending, jobsTotal, jobsLive, jobsPending;
  final int applicationsTotal, applications7d, hires, reportsOpen, jobViews;
  final List<({DateTime day, int count})> signups30d, applications30d, jobs30d;
  final Map<String, int> byStatus;
  final List<CountPoint> topIndustries, topLocations, topCompanies;
  final int activeUsers7d, companiesApproved, companiesRejected, companiesSuspended, companiesVerified;
  final int jobsDraft, jobsClosed, jobsClosing7d, jobsFeatured, avgSalary, hires30d, reportsTotal;

  /// Average days from application to the employer's first action (null = no data).
  final double? avgResponseDays;
  final List<CountPoint> byEmploymentType, byWorkMode, byExperience, seekerLocations, reportsByReason;

  /// Applications per posted (non-draft) job.
  double get applicationsPerJob => (jobsTotal - jobsDraft) <= 0 ? 0 : applicationsTotal / (jobsTotal - jobsDraft);

  /// Share of job views that turned into an application (null = no views).
  double? get viewToApply => jobViews == 0 ? null : applicationsTotal / jobViews;

  /// Share of reviewed companies that were approved (null = none reviewed).
  double? get approvalRate {
    final reviewed = companiesApproved + companiesRejected;
    return reviewed == 0 ? null : companiesApproved / reviewed;
  }

  int get pendingWork => companiesPending + jobsPending + reportsOpen;

  factory AdminStats.fromJson(Map<String, dynamic> j) {
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    List<({DateTime day, int count})> series(String k) => [
          for (final e in (j[k] as List? ?? const []))
            (day: DateTime.parse('${(e as Map)['day']}'), count: (e['count'] as num).toInt()),
        ];
    List<CountPoint> points(String k) => [
          for (final e in (j[k] as List? ?? const [])) CountPoint('${(e as Map)['label']}', (e['count'] as num).toInt()),
        ];
    return AdminStats(
      usersTotal: n('users_total'),
      seekers: n('seekers'),
      employers: n('employers'),
      suspended: n('suspended'),
      newUsers7d: n('new_users_7d'),
      companiesTotal: n('companies_total'),
      companiesPending: n('companies_pending'),
      jobsTotal: n('jobs_total'),
      jobsLive: n('jobs_live'),
      jobsPending: n('jobs_pending'),
      applicationsTotal: n('applications_total'),
      applications7d: n('applications_7d'),
      hires: n('hires'),
      reportsOpen: n('reports_open'),
      jobViews: n('job_views'),
      signups30d: series('signups_30d'),
      applications30d: series('applications_30d'),
      jobs30d: series('jobs_30d'),
      byStatus: {for (final e in Map<String, dynamic>.from(j['by_status'] as Map? ?? const {}).entries) e.key: (e.value as num).toInt()},
      topIndustries: points('top_industries'),
      topLocations: points('top_locations'),
      topCompanies: points('top_companies'),
      activeUsers7d: n('active_users_7d'),
      companiesApproved: n('companies_approved'),
      companiesRejected: n('companies_rejected'),
      companiesSuspended: n('companies_suspended'),
      companiesVerified: n('companies_verified'),
      jobsDraft: n('jobs_draft'),
      jobsClosed: n('jobs_closed'),
      jobsClosing7d: n('jobs_closing_7d'),
      jobsFeatured: n('jobs_featured'),
      avgSalary: n('avg_salary'),
      hires30d: n('hires_30d'),
      reportsTotal: n('reports_total'),
      avgResponseDays: (j['avg_response_days'] as num?)?.toDouble(),
      byEmploymentType: points('by_employment_type'),
      byWorkMode: points('by_work_mode'),
      byExperience: points('by_experience'),
      seekerLocations: points('seeker_locations'),
      reportsByReason: points('reports_by_reason'),
    );
  }
}

/// Moderation view of a job (with its company).
typedef AdminJob = Job;

enum InvoiceStatus {
  draft('Draft', 'draft'),
  issued('Issued', 'issued'),
  paid('Paid', 'paid'),
  voided('Void', 'void');

  const InvoiceStatus(this.label, this.dbName);
  final String label;
  final String dbName;

  static InvoiceStatus fromName(String? n) => values.firstWhere((s) => s.dbName == n, orElse: () => draft);
}

/// An invoice for a job listing. Totals are calculated the same way as the
/// database's generated columns: tax applies after the discount.
class Invoice {
  const Invoice({
    required this.id,
    required this.number,
    required this.createdAt,
    this.jobId,
    this.companyId,
    this.jobTitle = '',
    this.billToName = '',
    this.billToEmail = '',
    this.billToAddress = '',
    this.description = 'Job listing on Vocation SL',
    this.quantity = 1,
    this.unitPrice = 0,
    this.discount = 0,
    this.taxRate = 15,
    this.currency = 'SLE',
    this.status = InvoiceStatus.draft,
    this.issueDate,
    this.dueDate,
    this.paidAt,
    this.paymentMethod = '',
    this.paymentReference = '',
    this.notes = '',
  });

  final String id;
  final String number;
  final String? jobId;
  final String? companyId;
  final String jobTitle;
  final String billToName;
  final String billToEmail;
  final String billToAddress;
  final String description;
  final int quantity;
  final double unitPrice;
  final double discount;

  /// Percent, e.g. 15 for 15%.
  final double taxRate;
  final String currency;
  final InvoiceStatus status;
  final DateTime? issueDate;
  final DateTime? dueDate;
  final DateTime? paidAt;
  final String paymentMethod;
  final String paymentReference;
  final String notes;
  final DateTime createdAt;

  static double _round2(double v) => (v * 100).roundToDouble() / 100;

  double get subtotal => _round2(quantity * unitPrice);
  double get taxable => (subtotal - discount).clamp(0, double.infinity).toDouble();
  double get taxAmount => _round2(taxable * taxRate / 100);
  double get total => _round2(taxable + taxAmount);

  /// A draft with no cost entered yet.
  bool get needsPricing => status == InvoiceStatus.draft && unitPrice == 0;

  bool isOverdueAt(DateTime now) =>
      status == InvoiceStatus.issued && dueDate != null && DateTime(now.year, now.month, now.day).isAfter(dueDate!);

  Invoice copyWith({
    String? billToName,
    String? billToEmail,
    String? billToAddress,
    String? description,
    int? quantity,
    double? unitPrice,
    double? discount,
    double? taxRate,
    String? currency,
    InvoiceStatus? status,
    DateTime? Function()? issueDate,
    DateTime? Function()? dueDate,
    DateTime? Function()? paidAt,
    String? paymentMethod,
    String? paymentReference,
    String? notes,
  }) =>
      Invoice(
        id: id,
        number: number,
        createdAt: createdAt,
        jobId: jobId,
        companyId: companyId,
        jobTitle: jobTitle,
        billToName: billToName ?? this.billToName,
        billToEmail: billToEmail ?? this.billToEmail,
        billToAddress: billToAddress ?? this.billToAddress,
        description: description ?? this.description,
        quantity: quantity ?? this.quantity,
        unitPrice: unitPrice ?? this.unitPrice,
        discount: discount ?? this.discount,
        taxRate: taxRate ?? this.taxRate,
        currency: currency ?? this.currency,
        status: status ?? this.status,
        issueDate: issueDate == null ? this.issueDate : issueDate(),
        dueDate: dueDate == null ? this.dueDate : dueDate(),
        paidAt: paidAt == null ? this.paidAt : paidAt(),
        paymentMethod: paymentMethod ?? this.paymentMethod,
        paymentReference: paymentReference ?? this.paymentReference,
        notes: notes ?? this.notes,
      );

  static DateTime? _date(Object? v) => v == null ? null : DateTime.tryParse('$v');
  static String? _day(DateTime? d) => d == null
      ? null
      : '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
        id: j['id'] as String,
        number: j['number'] as String? ?? '',
        jobId: j['job_id'] as String?,
        companyId: j['company_id'] as String?,
        jobTitle: j['job_title'] as String? ?? '',
        billToName: j['bill_to_name'] as String? ?? '',
        billToEmail: j['bill_to_email'] as String? ?? '',
        billToAddress: j['bill_to_address'] as String? ?? '',
        description: j['description'] as String? ?? '',
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
        unitPrice: (j['unit_price'] as num?)?.toDouble() ?? 0,
        discount: (j['discount'] as num?)?.toDouble() ?? 0,
        taxRate: (j['tax_rate'] as num?)?.toDouble() ?? 15,
        currency: j['currency'] as String? ?? 'SLE',
        status: InvoiceStatus.fromName(j['status'] as String?),
        issueDate: _date(j['issue_date']),
        dueDate: _date(j['due_date']),
        paidAt: _date(j['paid_at']),
        paymentMethod: j['payment_method'] as String? ?? '',
        paymentReference: j['payment_reference'] as String? ?? '',
        notes: j['notes'] as String? ?? '',
        createdAt: _date(j['created_at']) ?? DateTime.now(),
      );

  /// Editable columns only (number, totals and job link are set by the database).
  Map<String, dynamic> toJson() => {
        'bill_to_name': billToName,
        'bill_to_email': billToEmail,
        'bill_to_address': billToAddress,
        'description': description,
        'quantity': quantity,
        'unit_price': unitPrice,
        'discount': discount,
        'tax_rate': taxRate,
        'currency': currency,
        'status': status.dbName,
        'issue_date': _day(issueDate),
        'due_date': _day(dueDate),
        'paid_at': paidAt?.toUtc().toIso8601String(),
        'payment_method': paymentMethod,
        'payment_reference': paymentReference,
        'notes': notes,
      };
}
