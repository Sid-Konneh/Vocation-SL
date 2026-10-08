import 'dart:typed_data';

import '../../models/models.dart';

/// The contract every backend implements. Repositories depend only on this,
/// so the demo backend can be swapped for Supabase, Firebase or a REST API
/// without touching the UI.
abstract interface class VocationBackend {
  String get name;

  // Auth
  String? get currentUserId;

  /// Emits the signed-in user id (or null) when the session changes outside
  /// a direct call, e.g. after returning from Google sign-in or a token expiry.
  Stream<String?> get authChanges;

  bool get supportsGoogleSignIn;

  /// The signed-in user's chosen role, or null if they haven't chosen yet.
  UserRole? get currentRole;
  Future<void> setRole(UserRole role);
  Future<String> signIn({required String email, required String password});

  /// Throws [EmailConfirmationRequired] when the account must be verified first.
  Future<String> signUp({required String fullName, required String email, required String password});

  /// Opens Google sign-in. The session arrives later through [authChanges].
  /// On the web, [intent] travels in the return URL (`?role=`) because a
  /// browser may drop storage writes when the page navigates to Google.
  Future<void> signInWithGoogle({UserRole? intent});
  Future<void> sendPasswordReset(String email);

  /// Fires when the user opens a password-reset link and should choose a new password.
  Stream<void> get passwordRecovery;
  Future<void> updatePassword(String newPassword);
  Future<void> signOut();

  /// Permanently deletes the signed-in user's account and data, then signs out.
  Future<void> deleteAccount();

  // Platform content (managed by admins)
  Future<List<Announcement>> fetchAnnouncements();
  Future<SitePage?> fetchPage(String slug);
  Future<PlatformSettings> fetchPlatformSettings();

  /// Whether an admin has suspended the signed-in account.
  Future<bool> isSuspended();

  /// Flags a job, company or user for the moderation team.
  Future<void> submitReport({required ReportTarget type, required String targetId, required String targetLabel, required String reason, String details = ''});

  // Catalogue. Jobs are returned with their [Company] attached.
  Future<List<Company>> fetchCompanies();
  Future<PageResult<Job>> searchJobs(JobFilter filter, {required int page, required int pageSize});
  Future<Job> fetchJob(String id);

  /// Counts a job-detail view for employer insights. Best effort.
  Future<void> recordJobView(String jobId);

  // Profile
  Future<AppUser> fetchUser(String userId);
  Future<AppUser> updateUser(AppUser user);

  /// Uploads a CV, cover letter or photo; returns the remote storage path.
  Future<String> uploadDocument({required String userId, required String fileName, required Uint8List bytes});

  /// Reads an uploaded CV and returns the profile details found in it.
  Future<CvExtract> readCv(String storagePath);

  /// A short-lived link to view one of the user's own uploaded documents.
  Future<String> documentUrl(String storagePath);

  // Applications
  Future<List<JobApplication>> fetchApplications(String userId);
  Future<JobApplication> submitApplication(JobApplication application);
  Future<JobApplication> withdrawApplication(String applicationId, {String? reason});

  // Notifications
  Future<List<AppNotification>> fetchNotifications(String userId);
  Future<void> markNotificationsRead(String userId, List<String> ids);
  Future<void> deleteNotification(String id);

  // Saved jobs and saved searches
  Future<List<SavedJob>> fetchSavedJobs(String userId);
  Future<void> saveJob(SavedJob saved);
  Future<void> unsaveJob(String userId, String jobId);
  Future<List<JobAlert>> fetchAlerts(String userId);
  Future<JobAlert> upsertAlert(JobAlert alert);
  Future<void> deleteAlert(String alertId);
}
