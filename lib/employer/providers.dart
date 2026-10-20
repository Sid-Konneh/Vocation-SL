import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../models/models.dart';
import '../providers/cache_first.dart';
import '../providers/core_providers.dart';
import '../providers/referral_providers.dart';
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

  /// A saved "no company yet" is never trusted: the company may have been
  /// created since (on this device as a job seeker who switched, or on
  /// another device), so always ask the server in that case.
  @override
  Loaded<Company?>? readCache() {
    final cached = ref.read(employerRepositoryProvider).peekCompany(_uid);
    return cached?.data == null ? null : cached;
  }
  @override
  bool get cacheIsFresh => ref.read(employerRepositoryProvider).fresh(_uid, 'company');
  @override
  Future<Loaded<Company?>> fetchRemote() => ref.read(employerRepositoryProvider).fetchCompany(_uid);

  /// Creates the company, then adds its logo and referral code before the
  /// dashboard opens. A failed logo or referral doesn't undo the sign-up; the
  /// reason is returned so the screen can explain it.
  Future<CompanySignUp> register(Company draft, {Uint8List? logoBytes, String logoName = 'logo.jpg', String referralCode = ''}) async {
    final backend = ref.read(employerBackendProvider);
    var c = await backend.registerCompany(draft);
    String? logoError, referralError;
    if (logoBytes != null) {
      try {
        c = await backend.uploadLogo(c, logoBytes, logoName);
      } catch (e) {
        logoError = AppException.describe(e);
      }
    }
    if (ReferralCode.normalize(referralCode).isNotEmpty) {
      try {
        await ref.read(referralBackendProvider).claim(referralCode, c.id);
      } catch (e) {
        referralError = AppException.describe(e);
      }
      await PendingReferral.clear(ref.read(localStoreProvider));
    }
    // Show the dashboard straight away with the company just created and keep
    // it on the device, so a slower background check can't send the employer
    // back to the setup screen.
    await _keep(c);
    // Jobs and applicants were loaded while there was no company; load them for this one.
    ref.invalidate(employerJobsProvider);
    ref.invalidate(candidatesProvider);
    return (company: c, logoError: logoError, referralError: referralError);
  }

  Future<void> _keep(Company c) async {
    setData(c);
    await ref.read(employerRepositoryProvider).cacheCompany(_uid, c);
  }

  Future<Company> save(Company company) async {
    final c = await ref.read(employerBackendProvider).updateCompany(company);
    await _keep(c);
    return c;
  }

  Future<Company> uploadLogo(Company company, Uint8List bytes, String fileName) async {
    final c = await ref.read(employerBackendProvider).uploadLogo(company, bytes, fileName);
    await _keep(c);
    // Job lists embed the company, so refresh them to show the new logo.
    ref.invalidate(employerJobsProvider);
    return c;
  }
}

final companyProvider = AsyncNotifierProvider<CompanyController, Loaded<Company?>>(CompanyController.new);

/// Result of creating a company: the company plus any part that didn't save.
typedef CompanySignUp = ({Company company, String? logoError, String? referralError});

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

/// The company's issued invoices (newest first).
final employerInvoicesProvider = FutureProvider.autoDispose<List<Invoice>>((ref) async {
  final company = (await ref.watch(companyProvider.future)).data;
  if (company == null) return const [];
  return ref.watch(employerBackendProvider).invoices(company.id);
});

/// Free postings left under the launch offer (refreshes when jobs change).
final launchOfferProvider = FutureProvider.autoDispose<LaunchOffer>((ref) {
  ref.watch(employerJobsProvider);
  return ref.watch(employerBackendProvider).launchOffer();
});

/// The company's team (owner and recruiters).
final teamProvider = FutureProvider.autoDispose<List<TeamMember>>((ref) {
  ref.watch(companyProvider);
  return ref.watch(employerBackendProvider).team();
});

final applicantProfileProvider = FutureProvider.autoDispose.family<AppUser?, String>(
  (ref, userId) => ref.watch(employerBackendProvider).applicantProfile(userId),
);

// ---- Derived ------------------------------------------------------------------------

/// Hiring statistics from whatever data is loaded (empty lists while loading).
final hiringStatsProvider = Provider<HiringStats>((ref) => HiringStats(
      jobs: ref.watch(employerJobsProvider).value?.data ?? const [],
      applications: ref.watch(candidatesProvider).value?.data ?? const [],
    ));
