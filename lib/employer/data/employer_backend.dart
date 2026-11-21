import 'dart:typed_data';

import '../../models/models.dart';

/// Data operations for the employer app. Access is enforced by row-level
/// security in Supabase (see supabase/employer_schema.sql): an employer only
/// ever receives their own company's jobs, applicants and documents.
/// Result of extending or reposting a job.
typedef JobExtension = ({DateTime deadline, JobStatus status, String invoice, num amount, bool free});

abstract interface class EmployerBackend {
  /// The company the signed-in user belongs to, or null if they haven't registered one.
  Future<Company?> myCompany();
  Future<Company> registerCompany(Company draft);
  Future<Company> updateCompany(Company company);

  /// Uploads a logo image (PNG/JPG/WebP, max 2 MB) and saves its URL on the company.
  Future<Company> uploadLogo(Company company, Uint8List bytes, String fileName);

  /// Uploads a job advert (PDF or image, max 5 MB) and returns its public URL,
  /// which is then saved on the job as [Job.advertUrl].
  Future<String> uploadJobAdvert(Uint8List bytes, String fileName);

  /// All of the company's jobs, any status.
  Future<List<Job>> myJobs(String companyId);

  /// Creates (when [job.id] is empty) or updates a job. The database decides
  /// the final status (e.g. 'pending' until the company is approved).
  Future<Job> saveJob(Job job, {required JobStatus status});
  Future<Job> setJobStatus(String jobId, JobStatus status);
  Future<void> deleteDraft(String jobId);

  /// Applications to the company's jobs, each with its [JobApplication.job].
  Future<List<JobApplication>> applications(String companyId);

  /// Moves a candidate through the pipeline and/or sends them a message.
  Future<JobApplication> updateApplication(
    JobApplication application, {
    ApplicationStatus? status,
    String? employerMessage,
    DateTime? interviewAt,
    bool clearInterview = false,
  });

  /// The applicant's full profile (visible only because they applied).
  Future<AppUser?> applicantProfile(String userId);

  /// A short-lived download link for a CV or cover letter.
  Future<String> documentUrl(String storagePath);

  /// Invoices for the company's job listings, once issued (drafts stay with admins).
  Future<List<Invoice>> invoices(String companyId);

  /// Free postings left under the launch offer.
  Future<LaunchOffer> launchOffer();

  /// Asks for a live job to be featured; returns the invoice number issued.
  Future<String> requestFeatured(String jobId);

  /// Extends a live job, or reposts a closed one, by [weeks] (1 to 4). The
  /// deadline moves on and an invoice for the extra weeks is created (a draft
  /// that Vocation SL issues; free for employers who post free).
  Future<JobExtension> extendJob(String jobId, int weeks);

  // Team access (the owner adds colleagues by email)
  Future<List<TeamMember>> team();
  /// Adds a colleague. Returns true if they already had an account and joined
  /// now; false if they were sent an invite and join when they sign up.
  Future<bool> addTeamMember(String email);
  Future<void> removeTeamMember(String userId);
  Future<void> cancelTeamInvite(String email);
}
