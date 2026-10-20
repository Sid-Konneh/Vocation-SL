import '../../models/models.dart';
import '../../repositories/base.dart';
import 'employer_backend.dart';

/// Cache-first access to employer data. Reads fall back to the last cached
/// copy when offline; writes require a connection (they change what
/// candidates see, so they are not queued).
class EmployerRepository extends CachedRepository {
  EmployerRepository(super.store, this.backend);
  final EmployerBackend backend;

  static const freshFor = Duration(minutes: 3);

  String _k(String uid, String what) => 'emp:$uid:$what';

  // Company
  Loaded<Company?>? peekCompany(String uid) =>
      peek(_k(uid, 'company'), (j) => j == null ? null : Company.fromJson(Map<String, dynamic>.from(j as Map)));
  Future<Loaded<Company?>> fetchCompany(String uid) => fetchAndCache(
        key: _k(uid, 'company'),
        fetch: backend.myCompany,
        encode: _encodeCompany,
        decode: (j) => j == null ? null : Company.fromJson(Map<String, dynamic>.from(j as Map)),
      );

  /// Saves a company just created or edited, so the next app start opens the
  /// dashboard instead of an out-of-date "set up your company" screen.
  Future<void> cacheCompany(String uid, Company c) => store.write(_k(uid, 'company'), _encodeCompany(c));

  static Object? _encodeCompany(Company? c) =>
      c == null ? null : {...c.toJson(), ...c.toEmployerJson(), 'status': c.status.name, 'owner_id': c.ownerId};

  // Jobs
  Loaded<List<Job>>? peekJobs(String uid) => peek(_k(uid, 'jobs'), _decodeJobs);
  Future<Loaded<List<Job>>> fetchJobs(String uid, String companyId) => fetchAndCache(
        key: _k(uid, 'jobs'),
        fetch: () => backend.myJobs(companyId),
        encode: (v) => v.map((j) => j.toJson()).toList(),
        decode: _decodeJobs,
      );
  List<Job> _decodeJobs(Object? j) => jsonList(j).map(Job.fromJson).toList();

  // Applications
  Loaded<List<JobApplication>>? peekApplications(String uid) => peek(_k(uid, 'apps'), _decodeApps);
  Future<Loaded<List<JobApplication>>> fetchApplications(String uid, String companyId) => fetchAndCache(
        key: _k(uid, 'apps'),
        fetch: () => backend.applications(companyId),
        encode: (v) => v.map((a) => a.toJson(includeJob: true)).toList(),
        decode: _decodeApps,
      );
  List<JobApplication> _decodeApps(Object? j) => jsonList(j).map(JobApplication.fromJson).toList();

  bool fresh(String uid, String what) => isFresh(_k(uid, what), freshFor);

  Future<void> clearFor(String uid) async {
    for (final k in store.keysWithPrefix('emp:$uid:').toList()) {
      await store.remove(k);
    }
  }
}
