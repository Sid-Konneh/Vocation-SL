import '../../models/models.dart';

/// Data operations for the employer app. Access is enforced by row-level
/// security in Supabase (see supabase/employer_schema.sql): an employer only
/// ever receives their own company's jobs, applicants and documents.
abstract interface class EmployerBackend {
  /// The company the signed-in user belongs to, or null if they haven't registered one.
  Future<Company?> myCompany();
  Future<Company> registerCompany(Company draft);
  Future<Company> updateCompany(Company company);

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
}
