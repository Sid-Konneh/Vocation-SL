import 'dart:convert';
import 'dart:typed_data';

import '../../core/errors.dart';
import '../../models/models.dart';
import 'employer_backend.dart';

/// In-memory employer backend for demo mode and tests. Mirrors the database
/// rules in supabase/employer_schema.sql (approval gating, employer-editable
/// fields only). Data resets when the app restarts.
class DemoEmployerBackend implements EmployerBackend {
  DemoEmployerBackend({this.approveOnRegister = false});

  final bool approveOnRegister;

  Company? company;
  final jobs = <Job>[];
  final apps = <JobApplication>[];

  @override
  Future<Company?> myCompany() async => company;

  @override
  Future<Company> registerCompany(Company draft) async {
    company = Company(
      id: 'co-1',
      name: draft.name,
      industry: draft.industry,
      location: draft.location,
      about: draft.about,
      size: draft.size,
      founded: draft.founded,
      website: draft.website,
      brandColor: draft.brandColor,
      email: draft.email,
      phone: draft.phone,
      address: draft.address,
      tin: draft.tin,
      status: approveOnRegister ? CompanyStatus.approved : CompanyStatus.pending,
    );
    return company!;
  }

  @override
  Future<Company> updateCompany(Company c) async => company = c;

  @override
  Future<Company> uploadLogo(Company c, Uint8List bytes, String fileName) async {
    final type = fileName.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
    return company = c.copyWith(logoUrl: () => 'data:$type;base64,${base64Encode(bytes)}');
  }

  @override
  Future<List<Job>> myJobs(String companyId) async => List.of(jobs);

  Job _with(Job j, {required String id, required JobStatus status}) => Job(
        id: id,
        title: j.title,
        companyId: j.companyId,
        location: j.location,
        employmentType: j.employmentType,
        workMode: j.workMode,
        industry: j.industry,
        experienceLevel: j.experienceLevel,
        salaryMin: j.salaryMin,
        salaryMax: j.salaryMax,
        postedAt: DateTime.now(),
        deadline: j.deadline,
        about: j.about,
        description: j.description,
        responsibilities: j.responsibilities,
        requirements: j.requirements,
        preferred: j.preferred,
        skills: j.skills,
        benefits: j.benefits,
        status: status,
        company: company,
      );

  @override
  Future<Job> saveJob(Job job, {required JobStatus status}) async {
    final effective = status == JobStatus.published && !(company?.isApproved ?? false) ? JobStatus.pending : status;
    final saved = _with(job, id: job.id.isEmpty ? 'job-${jobs.length + 1}' : job.id, status: effective);
    jobs.removeWhere((j) => j.id == saved.id);
    jobs.insert(0, saved);
    return saved;
  }

  @override
  Future<Job> setJobStatus(String jobId, JobStatus status) async {
    final j = jobs.firstWhere((x) => x.id == jobId);
    return saveJob(j, status: status);
  }

  @override
  Future<void> deleteDraft(String jobId) async => jobs.removeWhere((j) => j.id == jobId && j.status == JobStatus.draft);

  @override
  Future<List<JobApplication>> applications(String companyId) async => List.of(apps);

  @override
  Future<JobApplication> updateApplication(JobApplication a,
      {ApplicationStatus? status, String? employerMessage, DateTime? interviewAt, bool clearInterview = false}) async {
    if (status == ApplicationStatus.withdrawn) throw const ValidationException('Only the candidate can withdraw an application.');
    final next = status ?? a.status;
    final updated = a.copyWith(
      status: next,
      history: next == a.status ? a.history : [...a.history, StatusEvent(status: next, at: DateTime.now())],
      employerMessage: employerMessage == null ? null : () => employerMessage,
      interviewAt: clearInterview ? () => null : (interviewAt == null ? null : () => interviewAt),
    );
    apps[apps.indexWhere((x) => x.id == a.id)] = updated;
    return updated;
  }

  @override
  Future<AppUser?> applicantProfile(String userId) async {
    final a = apps.where((x) => x.userId == userId).firstOrNull;
    if (a == null) return null;
    return AppUser(id: userId, fullName: a.applicant.fullName, email: a.applicant.email, phone: a.applicant.phone, location: a.applicant.location);
  }

  @override
  Future<String> documentUrl(String storagePath) async =>
      throw const ValidationException('Demo mode has no stored files to download.');

  /// Adds an applicant to [jobId] (simulates a job seeker applying).
  JobApplication addApplicant(String jobId, String name, {DateTime? at}) {
    final when = at ?? DateTime.now().subtract(const Duration(hours: 3));
    final app = JobApplication(
      id: 'app-${apps.length + 1}',
      jobId: jobId,
      userId: 'user-${apps.length + 1}',
      status: ApplicationStatus.applied,
      submittedAt: when,
      history: [StatusEvent(status: ApplicationStatus.applied, at: when)],
      applicant: ApplicantInfo(fullName: name, email: '${name.split(' ').first.toLowerCase()}@example.com', phone: '+232 76 000 111', location: 'Freetown'),
      resume: Resume(id: 'r', fileName: '${name.replaceAll(' ', '_')}_CV.pdf', sizeBytes: 120000, uploadedAt: when, format: DocumentFormat.pdf, storagePath: 'u/cv.pdf'),
      job: jobs.firstWhere((j) => j.id == jobId),
    );
    apps.insert(0, app);
    return app;
  }
}
