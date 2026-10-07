import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../models/models.dart';
import '../providers/cache_first.dart';
import '../providers/core_providers.dart';
import '../providers/session_providers.dart';
import '../repositories/base.dart';
import 'data/employer_backend.dart';
import 'data/employer_repository.dart';
import 'insights.dart';

/// Injected in main_employer.dart.
final employerBackendProvider = Provider<EmployerBackend>((ref) => throw UnimplementedError('Override in main_employer'));

final employerRepositoryProvider =
    Provider((ref) => EmployerRepository(ref.watch(localStoreProvider), ref.watch(employerBackendProvider)));

// ---- Company -------------------------------------------------------------------

class CompanyController extends CacheFirstNotifier<Company?> {
  late String _uid;

  @override
  Future<Loaded<Company?>> build() {
    _uid = requireUid(ref);
    return super.build();
  }

  @override
  Loaded<Company?>? readCache() => ref.read(employerRepositoryProvider).peekCompany(_uid);
  @override
  bool get cacheIsFresh => ref.read(employerRepositoryProvider).fresh(_uid, 'company');
  @override
  Future<Loaded<Company?>> fetchRemote() => ref.read(employerRepositoryProvider).fetchCompany(_uid);

  Future<Company> register(Company draft) async {
    final c = await ref.read(employerBackendProvider).registerCompany(draft);
    await refresh();
    return c;
  }

  Future<Company> save(Company company) async {
    final c = await ref.read(employerBackendProvider).updateCompany(company);
    setData(c);
    return c;
  }

  Future<Company> uploadLogo(Company company, Uint8List bytes, String fileName) async {
    final c = await ref.read(employerBackendProvider).uploadLogo(company, bytes, fileName);
    setData(c);
    // Job lists embed the company, so refresh them to show the new logo.
    ref.invalidate(employerJobsProvider);
    return c;
  }
}

final companyProvider = AsyncNotifierProvider<CompanyController, Loaded<Company?>>(CompanyController.new);

/// The company, or throws if not loaded / not registered. For screens behind onboarding.
Company requireCompany(Ref ref) {
  final c = ref.watch(companyProvider).value?.data;
  if (c == null) throw const NotFoundException('No company');
  return c;
}

// ---- Jobs ------------------------------------------------------------------------

class EmployerJobsController extends CacheFirstNotifier<List<Job>> {
  late String _uid;
  late String _companyId;

  @override
  Future<Loaded<List<Job>>> build() async {
    _uid = requireUid(ref);
    _companyId = (await ref.watch(companyProvider.future)).data?.id ?? '';
    if (_companyId.isEmpty) return const Loaded(<Job>[]);
    return super.build();
  }

  @override
  Loaded<List<Job>>? readCache() => ref.read(employerRepositoryProvider).peekJobs(_uid);
  @override
  bool get cacheIsFresh => ref.read(employerRepositoryProvider).fresh(_uid, 'jobs');
  @override
  Future<Loaded<List<Job>>> fetchRemote() => ref.read(employerRepositoryProvider).fetchJobs(_uid, _companyId);

  Future<Job> save(Job job, {required JobStatus status}) async {
    final saved = await ref.read(employerBackendProvider).saveJob(job, status: status);
    final list = dataOrNull ?? const <Job>[];
    setData([saved, ...list.where((j) => j.id != saved.id)]);
    return saved;
  }

  Future<Job> setStatus(Job job, JobStatus status) async {
    final saved = await ref.read(employerBackendProvider).setJobStatus(job.id, status);
    setData([for (final j in dataOrNull ?? const <Job>[]) j.id == saved.id ? saved : j]);
    return saved;
  }

  Future<void> deleteDraft(Job job) async {
    await ref.read(employerBackendProvider).deleteDraft(job.id);
    setData((dataOrNull ?? const <Job>[]).where((j) => j.id != job.id).toList());
  }
}

final employerJobsProvider = AsyncNotifierProvider<EmployerJobsController, Loaded<List<Job>>>(EmployerJobsController.new);

// ---- Applications (ATS) --------------------------------------------------------------

class CandidatesController extends CacheFirstNotifier<List<JobApplication>> {
  late String _uid;
  late String _companyId;

  @override
  Future<Loaded<List<JobApplication>>> build() async {
    _uid = requireUid(ref);
    _companyId = (await ref.watch(companyProvider.future)).data?.id ?? '';
    if (_companyId.isEmpty) return const Loaded(<JobApplication>[]);
    return super.build();
  }

  @override
  Loaded<List<JobApplication>>? readCache() => ref.read(employerRepositoryProvider).peekApplications(_uid);
  @override
  bool get cacheIsFresh => ref.read(employerRepositoryProvider).fresh(_uid, 'apps');
  @override
  Future<Loaded<List<JobApplication>>> fetchRemote() => ref.read(employerRepositoryProvider).fetchApplications(_uid, _companyId);

  Future<JobApplication> updateCandidate(
    JobApplication app, {
    ApplicationStatus? status,
    String? message,
    DateTime? interviewAt,
    bool clearInterview = false,
  }) async {
    final saved = await ref.read(employerBackendProvider).updateApplication(
          app,
          status: status,
          employerMessage: message,
          interviewAt: interviewAt,
          clearInterview: clearInterview,
        );
    final withJob = saved.job == null ? saved.copyWith(job: () => app.job) : saved;
    setData([for (final a in dataOrNull ?? const <JobApplication>[]) a.id == withJob.id ? withJob : a]);
    return withJob;
  }

  /// Opening an application for the first time marks it as viewed.
  Future<void> markViewed(JobApplication app) async {
    if (app.status != ApplicationStatus.applied) return;
    try {
      await updateCandidate(app, status: ApplicationStatus.viewed);
    } catch (_) {
      // Not critical; retried next time it's opened.
    }
  }
}

final candidatesProvider =
    AsyncNotifierProvider<CandidatesController, Loaded<List<JobApplication>>>(CandidatesController.new);

final applicantProfileProvider = FutureProvider.autoDispose.family<AppUser?, String>(
  (ref, userId) => ref.watch(employerBackendProvider).applicantProfile(userId),
);

// ---- Derived ------------------------------------------------------------------------

/// Hiring statistics from whatever data is loaded (empty lists while loading).
final hiringStatsProvider = Provider<HiringStats>((ref) => HiringStats(
      jobs: ref.watch(employerJobsProvider).value?.data ?? const [],
      applications: ref.watch(candidatesProvider).value?.data ?? const [],
    ));
