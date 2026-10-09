import 'dart:convert';
import 'dart:typed_data';

import '../../core/errors.dart';
import '../../models/models.dart';
import 'employer_backend.dart';

/// In-memory employer backend for demo mode and tests. Mirrors the database
/// rules in supabase/employer_schema.sql (approval gating, employer-editable
/// fields only). Data resets when the app restarts.
class DemoEmployerBackend implements EmployerBackend {
  DemoEmployerBackend({this.approveOnRegister = false, this.withSamples = false});

  final bool approveOnRegister;

  /// Demo mode: registering a company also adds two sample jobs with sample
  /// applicants, so every employer screen has something to show.
  final bool withSamples;

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
      status: approveOnRegister || withSamples ? CompanyStatus.approved : CompanyStatus.pending,
    );
    if (withSamples) _addSamples();
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
  Future<void> deleteDraft(String jobId) async =>
      jobs.removeWhere((j) => j.id == jobId && const {JobStatus.draft, JobStatus.declined, JobStatus.rejected}.contains(j.status));

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
  Future<List<Invoice>> invoices(String companyId) async {
    // A sample issued invoice for the first live job, so the screen can be tried in demo mode.
    final live = jobs.where((j) => j.status == JobStatus.published).toList();
    if (live.isEmpty) return const [];
    final now = DateTime.now();
    final issued = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 2));
    return [
      Invoice(
        id: 'demo-inv-1',
        number: 'VSL-${now.year}-00001',
        createdAt: issued,
        jobId: live.first.id,
        companyId: companyId,
        jobTitle: live.first.title,
        billToName: company?.name ?? '',
        billToEmail: company?.email ?? '',
        unitPrice: 500,
        status: InvoiceStatus.issued,
        issueDate: issued,
        dueDate: issued.add(const Duration(days: 14)),
      ),
    ];
  }

  @override
  Future<String> documentUrl(String storagePath) async =>
      throw const ValidationException('Demo mode has no stored files to download.');

  void _addSamples() {
    final now = DateTime.now();
    Job job(String id, String title, String location, int min, int max, List<String> skills, int views) => Job(
          id: id,
          title: title,
          companyId: company!.id,
          location: location,
          employmentType: EmploymentType.fullTime,
          workMode: WorkMode.onsite,
          industry: company!.industry,
          experienceLevel: ExperienceLevel.mid,
          salaryMin: min,
          salaryMax: max,
          postedAt: now.subtract(const Duration(days: 6)),
          deadline: now.add(const Duration(days: 21)),
          about: 'Join our growing team in $location.',
          description: 'A sample job created for demo mode.',
          responsibilities: const ['Day-to-day duties for this role'],
          requirements: const ['Relevant qualification', 'Two years of experience'],
          preferred: const [],
          skills: skills,
          benefits: const ['Medical cover', 'Transport allowance'],
          status: JobStatus.published,
          company: company,
          views: views,
        );
    jobs.addAll([
      job('job-s1', 'Accounts Assistant', 'Freetown', 6000, 8000, const ['Bookkeeping', 'Excel', 'QuickBooks'], 214),
      job('job-s2', 'Sales Representative', 'Bo', 4500, 6500, const ['Sales', 'Customer service'], 131),
    ]);
    final people = [
      ('job-s1', 'Fatmata Kamara', ApplicationStatus.interview, 5),
      ('job-s1', 'Mohamed Bangura', ApplicationStatus.shortlisted, 4),
      ('job-s1', 'Isatu Conteh', ApplicationStatus.applied, 1),
      ('job-s1', 'Abdul Sesay', ApplicationStatus.viewed, 3),
      ('job-s2', 'Mariama Koroma', ApplicationStatus.applied, 2),
      ('job-s2', 'Ibrahim Turay', ApplicationStatus.offer, 6),
    ];
    for (final (jobId, name, status, daysAgo) in people) {
      final a = addApplicant(jobId, name, at: now.subtract(Duration(days: daysAgo, hours: 2)));
      if (status == ApplicationStatus.applied) continue;
      apps[apps.indexWhere((x) => x.id == a.id)] = a.copyWith(
        status: status,
        history: [...a.history, StatusEvent(status: status, at: now.subtract(Duration(days: daysAgo - 1)))],
        interviewAt: status == ApplicationStatus.interview ? () => DateTime(now.year, now.month, now.day + 2, 10) : null,
      );
    }
  }

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
