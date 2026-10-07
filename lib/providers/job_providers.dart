import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/errors.dart';
import '../models/models.dart';
import '../repositories/base.dart';
import 'cache_first.dart';
import 'core_providers.dart';

// ---- Companies ---------------------------------------------------------------

class CompaniesController extends CacheFirstNotifier<List<Company>> {
  @override
  Loaded<List<Company>>? readCache() => ref.read(jobRepositoryProvider).peekCompanies();
  @override
  bool get cacheIsFresh => ref.read(jobRepositoryProvider).isFresh('companies', CacheTtl.companies);
  @override
  Future<Loaded<List<Company>>> fetchRemote() => ref.read(jobRepositoryProvider).fetchCompanies();
}

final companiesProvider = AsyncNotifierProvider<CompaniesController, Loaded<List<Company>>>(CompaniesController.new);

// ---- Paged job search ----------------------------------------------------------

class JobSearchState {
  const JobSearchState({
    required this.filter,
    this.jobs = const [],
    this.page = 0,
    this.hasMore = true,
    this.loading = true,
    this.loadingMore = false,
    this.refreshing = false,
    this.error,
    this.loadMoreError,
    this.offlineCopy = false,
    this.syncedAt,
    this.total,
  });

  final JobFilter filter;
  final List<Job> jobs;
  final int page;
  final bool hasMore;

  /// First page loading with nothing to show yet.
  final bool loading;
  final bool loadingMore;
  final bool refreshing;
  final AppException? error;
  final AppException? loadMoreError;
  final bool offlineCopy;
  final DateTime? syncedAt;
  final int? total;

  bool get isEmpty => !loading && error == null && jobs.isEmpty;

  JobSearchState copyWith({
    JobFilter? filter,
    List<Job>? jobs,
    int? page,
    bool? hasMore,
    bool? loading,
    bool? loadingMore,
    bool? refreshing,
    AppException? Function()? error,
    AppException? Function()? loadMoreError,
    bool? offlineCopy,
    DateTime? Function()? syncedAt,
    int? Function()? total,
  }) =>
      JobSearchState(
        filter: filter ?? this.filter,
        jobs: jobs ?? this.jobs,
        page: page ?? this.page,
        hasMore: hasMore ?? this.hasMore,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        refreshing: refreshing ?? this.refreshing,
        error: error != null ? error() : this.error,
        loadMoreError: loadMoreError != null ? loadMoreError() : this.loadMoreError,
        offlineCopy: offlineCopy ?? this.offlineCopy,
        syncedAt: syncedAt != null ? syncedAt() : this.syncedAt,
        total: total != null ? total() : this.total,
      );
}

/// Paged, cache-first job search with infinite scroll.
class JobSearchController extends Notifier<JobSearchState> {
  JobSearchController(this.initialFilter);
  final JobFilter initialFilter;

  int _request = 0;

  @override
  JobSearchState build() {
    final state = JobSearchState(filter: initialFilter);
    Future.microtask(() => _loadFirst(initialFilter));
    return state;
  }

  void setFilter(JobFilter f) {
    if (f.cacheKey == state.filter.cacheKey) return;
    _loadFirst(f);
  }

  void setQuery(String q) => setFilter(state.filter.copyWith(query: q));

  Future<void> refresh() => _loadFirst(state.filter, pullToRefresh: true);

  Future<void> _loadFirst(JobFilter f, {bool pullToRefresh = false}) async {
    final req = ++_request;
    final repo = ref.read(jobRepositoryProvider);
    final cached = pullToRefresh ? null : repo.peekPage(f, 0);

    if (cached != null) {
      // Show cached results immediately, refresh in the background.
      state = JobSearchState(
        filter: f,
        jobs: cached.data.items,
        hasMore: cached.data.hasMore,
        loading: false,
        refreshing: true,
        offlineCopy: false,
        syncedAt: cached.syncedAt,
        total: cached.data.total,
      );
      if (repo.isPageFresh(f, 0)) {
        state = state.copyWith(refreshing: false);
        return;
      }
    } else {
      state = pullToRefresh
          ? state.copyWith(refreshing: true, error: () => null)
          : JobSearchState(filter: f, loading: true);
    }

    try {
      final result = await repo.searchJobs(f);
      if (!ref.mounted || req != _request) return;
      state = JobSearchState(
        filter: f,
        jobs: result.data.items,
        page: 0,
        hasMore: result.data.hasMore,
        loading: false,
        offlineCopy: result.isOfflineCopy,
        syncedAt: result.syncedAt,
        total: result.data.total,
      );
    } on AppException catch (e) {
      if (!ref.mounted || req != _request) return;
      state = state.jobs.isEmpty
          ? state.copyWith(loading: false, refreshing: false, error: () => e)
          : state.copyWith(loading: false, refreshing: false, offlineCopy: true);
    }
  }

  Future<void> loadMore() async {
    final s = state;
    if (s.loading || s.loadingMore || !s.hasMore || s.error != null) return;
    final req = _request;
    state = s.copyWith(loadingMore: true, loadMoreError: () => null);
    try {
      final result = await ref.read(jobRepositoryProvider).searchJobs(s.filter, page: s.page + 1);
      if (!ref.mounted || req != _request) return;
      final seen = state.jobs.map((j) => j.id).toSet();
      state = state.copyWith(
        jobs: [...state.jobs, ...result.data.items.where((j) => !seen.contains(j.id))],
        page: s.page + 1,
        hasMore: result.data.hasMore,
        loadingMore: false,
        offlineCopy: state.offlineCopy || result.isOfflineCopy,
      );
    } on AppException catch (e) {
      if (!ref.mounted || req != _request) return;
      state = state.copyWith(loadingMore: false, loadMoreError: () => e);
    }
  }
}

/// Home feed: newest jobs.
final homeFeedProvider = NotifierProvider<JobSearchController, JobSearchState>(
  () => JobSearchController(const JobFilter(sort: JobSort.newest)),
);

/// The search screen's results.
final searchProvider = NotifierProvider<JobSearchController, JobSearchState>(
  () => JobSearchController(JobFilter.empty),
);

/// Jobs for one company (company page).
final companyJobsProvider = NotifierProvider.autoDispose.family<JobSearchController, JobSearchState, String>(
  (companyId) => JobSearchController(JobFilter(companyId: companyId, sort: JobSort.newest)),
);

// ---- Job details -------------------------------------------------------------

class JobDetailController extends CacheFirstNotifier<Job> {
  JobDetailController(this.jobId);
  final String jobId;

  @override
  Future<Loaded<Job>> build() {
    if (ref.read(onlineProvider)) unawaited(ref.read(backendProvider).recordJobView(jobId));
    return super.build();
  }

  @override
  Loaded<Job>? readCache() => ref.read(jobRepositoryProvider).peekJob(jobId);
  @override
  bool get cacheIsFresh => ref.read(jobRepositoryProvider).isJobFresh(jobId);
  @override
  Future<Loaded<Job>> fetchRemote() => ref.read(jobRepositoryProvider).fetchJob(jobId);
}

final jobDetailProvider =
    AsyncNotifierProvider.autoDispose.family<JobDetailController, Loaded<Job>, String>(JobDetailController.new);

// ---- Recent searches -----------------------------------------------------------

class RecentSearchesNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => (ref.watch(localStoreProvider).setting<List<dynamic>>('recent_searches') ?? const []).cast<String>();

  Future<void> add(String q) async {
    final t = q.trim();
    if (t.isEmpty) return;
    state = [t, ...state.where((s) => s.toLowerCase() != t.toLowerCase())].take(8).toList();
    await ref.read(localStoreProvider).setSetting('recent_searches', state);
  }

  Future<void> clear() async {
    state = const [];
    await ref.read(localStoreProvider).setSetting('recent_searches', state);
  }
}

final recentSearchesProvider = NotifierProvider<RecentSearchesNotifier, List<String>>(RecentSearchesNotifier.new);
