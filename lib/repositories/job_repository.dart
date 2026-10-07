import '../core/config/app_config.dart';
import '../core/errors.dart';
import '../data/backend/backend.dart';
import '../models/models.dart';
import 'base.dart';

class JobRepository extends CachedRepository {
  JobRepository(super.store, this.backend);
  final VocationBackend backend;

  static const _index = 'jobs_index';
  String _pageKey(JobFilter f, int page) => 'jobs:${f.cacheKey}:$page';

  // ---- Companies -------------------------------------------------------------

  Loaded<List<Company>>? peekCompanies() => peek('companies', _decodeCompanies);

  Future<Loaded<List<Company>>> fetchCompanies() => fetchAndCache(
        key: 'companies',
        fetch: backend.fetchCompanies,
        encode: (v) => v.map((c) => c.toJson()).toList(),
        decode: _decodeCompanies,
      );

  List<Company> _decodeCompanies(Object? j) => jsonList(j).map(Company.fromJson).toList();

  // ---- Search ----------------------------------------------------------------

  Loaded<PageResult<Job>>? peekPage(JobFilter f, int page) => peek(_pageKey(f, page), _decodePage);
  bool isPageFresh(JobFilter f, int page) => isFresh(_pageKey(f, page), CacheTtl.jobs);

  Future<Loaded<PageResult<Job>>> searchJobs(JobFilter f, {int page = 0}) async {
    final key = _pageKey(f, page);
    try {
      final result = await backend.searchJobs(f, page: page, pageSize: AppConfig.pageSize);
      await store.write(key, _encodePage(result));
      await _addToIndex(result.items);
      return Loaded(result, syncedAt: DateTime.now());
    } on AppException catch (e) {
      if (e is! NetworkException && e is! ServerException) rethrow;
      final cached = peek(key, _decodePage);
      if (cached != null) return Loaded(cached.data, syncedAt: cached.syncedAt, fromCache: true, error: e);
      // No cached copy of this exact search: search every job we have seen.
      final known = _knownJobs();
      if (known.isEmpty) rethrow;
      final all = f.apply(known);
      final start = page * AppConfig.pageSize;
      final items = start >= all.length ? <Job>[] : all.skip(start).take(AppConfig.pageSize).toList();
      return Loaded(
        PageResult(items: items, page: page, hasMore: start + AppConfig.pageSize < all.length, total: all.length),
        fromCache: true,
        error: e,
      );
    }
  }

  Object _encodePage(PageResult<Job> r) => {
        'items': r.items.map((j) => j.toJson()).toList(),
        'page': r.page,
        'has_more': r.hasMore,
        'total': r.total,
      };

  PageResult<Job> _decodePage(Object? j) {
    final m = Map<String, dynamic>.from(j as Map);
    return PageResult(
      items: jsonList(m['items']).map(Job.fromJson).toList(),
      page: m['page'] as int,
      hasMore: m['has_more'] as bool,
      total: m['total'] as int?,
    );
  }

  // ---- Job details -----------------------------------------------------------

  Loaded<Job>? peekJob(String id) {
    final direct = peek('job:$id', (j) => Job.fromJson(Map<String, dynamic>.from(j as Map)));
    if (direct != null) return direct;
    final idx = store.read(_index);
    final raw = idx == null ? null : (idx.data as Map?)?[id];
    return raw == null ? null : Loaded(Job.fromJson(Map<String, dynamic>.from(raw as Map)), syncedAt: idx!.savedAt, fromCache: true);
  }

  bool isJobFresh(String id) => isFresh('job:$id', CacheTtl.jobDetail);

  Future<Loaded<Job>> fetchJob(String id) async {
    try {
      final job = await backend.fetchJob(id);
      await store.write('job:$id', job.toJson());
      await _addToIndex([job]);
      return Loaded(job, syncedAt: DateTime.now());
    } on AppException catch (e) {
      if (e is! NetworkException && e is! ServerException) rethrow;
      final cached = peekJob(id);
      if (cached != null) return Loaded(cached.data, syncedAt: cached.syncedAt, fromCache: true, error: e);
      rethrow;
    }
  }

  // ---- Index of every job seen, for offline search ----------------------------

  List<Job> _knownJobs() {
    final idx = store.read(_index);
    final map = idx?.data as Map?;
    if (map == null) return const [];
    return map.values.map((v) => Job.fromJson(Map<String, dynamic>.from(v as Map))).toList();
  }

  Future<void> _addToIndex(List<Job> jobs) async {
    if (jobs.isEmpty) return;
    final map = Map<String, dynamic>.from(store.read(_index)?.data as Map? ?? const {});
    for (final j in jobs) {
      map[j.id] = j.toJson();
    }
    await store.write(_index, map);
  }

  Future<void> rememberJobs(List<Job> jobs) => _addToIndex(jobs);
}
