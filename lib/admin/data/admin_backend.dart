import '../../models/models.dart';

/// Everything the admin dashboard reads and writes. Permissions are enforced
/// by the database (supabase/admin_schema.sql); the app only hides controls
/// a role cannot use.
abstract interface class AdminBackend {
  /// The signed-in user's admin role, or null if they are not an admin.
  Future<AdminRole?> myRole();

  Future<AdminStats> stats();

  // Job moderation
  Future<List<Job>> jobs();
  /// Approve (published), decline (send back), reject, close or reopen.
  /// [note] is the reason shown to the employer when declining or rejecting.
  Future<void> setJobStatus(String jobId, JobStatus status, {String note = ''});
  Future<void> setJobFeatured(String jobId, bool featured);
  Future<void> deleteJob(String jobId);

  // Employer verification
  Future<List<AdminCompany>> companies();
  Future<void> setCompanyStatus(String companyId, CompanyStatus status);
  Future<void> setCompanyVerified(String companyId, bool verified);

  // Users
  Future<List<AdminUser>> users();
  Future<void> setUserSuspended(String userId, bool suspended, {String? reason});
  Future<void> deleteUser(String userId);

  /// Sign-in details from the auth system (admins and owners only; logged).
  Future<UserLoginInfo?> userLogin(String userId);

  // Applications (platform-wide tracking)
  Future<List<JobApplication>> applications();

  /// A short-lived link to an applicant's CV or cover letter (moderators and up).
  Future<String> documentUrl(String storagePath);

  // Reports
  Future<List<Report>> reports();
  Future<void> updateReport(String reportId, ReportStatus status, {String note = ''});

  // Content
  Future<List<Announcement>> announcements();
  Future<void> saveAnnouncement(Announcement a);
  Future<void> deleteAnnouncement(String id);
  Future<List<SitePage>> pages();
  Future<void> savePage(String slug, String title, String body);

  // Settings
  Future<PlatformSettings> settings();
  Future<void> saveSettings(PlatformSettings s);

  // Admin team
  Future<List<AdminMember>> team();
  Future<void> addMember(String email, AdminRole role);
  Future<void> setMemberRole(String userId, AdminRole role);
  Future<void> removeMember(String userId);

  // Invoices (a draft is created for every job when it goes live)
  Future<List<Invoice>> invoices();
  Future<void> saveInvoice(Invoice invoice);
  Future<void> deleteInvoice(String id);

  // Activity log
  Future<List<AuditEntry>> activity({int limit = 300});
}
