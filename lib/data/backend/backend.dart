import 'dart:typed_data';

import '../../models/models.dart';

/// The contract every backend implements. Repositories depend only on this,
/// so the demo backend can be swapped for Supabase, Firebase or a REST API
/// without touching the UI.
abstract interface class VocationBackend {
  String get name;

  // Auth
  String? get currentUserId;
  Future<String> signIn({required String email, required String password});
  Future<String> signUp({required String fullName, required String email, required String password});
  Future<void> signOut();

  // Catalogue. Jobs are returned with their [Company] attached.
  Future<List<Company>> fetchCompanies();
  Future<PageResult<Job>> searchJobs(JobFilter filter, {required int page, required int pageSize});
  Future<Job> fetchJob(String id);

  // Profile
  Future<AppUser> fetchUser(String userId);
  Future<AppUser> updateUser(AppUser user);

  /// Uploads a CV, cover letter or photo; returns the remote storage path.
  Future<String> uploadDocument({required String userId, required String fileName, required Uint8List bytes});

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
