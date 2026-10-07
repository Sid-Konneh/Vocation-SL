import '../core/errors.dart';
import '../data/backend/backend.dart';
import '../models/models.dart';
import 'base.dart';
import 'sync_service.dart';

class ApplicationRepository extends CachedRepository {
  ApplicationRepository(super.store, this.backend, this.sync) {
    sync.register(
      'submit_application',
      (p) async => backend.submitApplication(JobApplication.fromJson(p)),
      onRejected: (p) => _removePending(p['id'] as String),
    );
    sync.register('withdraw_application', (p) async {
      await backend.withdrawApplication(p['id'] as String, reason: p['reason'] as String?);
    });
  }

  final VocationBackend backend;
  final SyncService sync;

  String _key(String uid) => 'u:$uid:applications';
  String _pendingKey(String uid) => 'u:$uid:pending_applications';

  List<JobApplication> _decode(Object? j) => jsonList(j).map(JobApplication.fromJson).toList();
  Object _encode(List<JobApplication> v) => v.map((a) => a.toJson(includeJob: true)).toList();

  List<JobApplication> _pending(String uid) => peek(_pendingKey(uid), _decode)?.data ?? const [];

  /// Merges submissions still waiting in the outbox into a server list.
  Loaded<List<JobApplication>> _withPending(String uid, Loaded<List<JobApplication>> l) {
    final pending = _pending(uid).where((p) => !l.data.any((a) => a.id == p.id)).toList();
    return pending.isEmpty ? l : l.withData([...pending, ...l.data]);
  }

  Loaded<List<JobApplication>>? peekAll(String uid) {
    final cached = peek(_key(uid), _decode);
    if (cached == null) return _pending(uid).isEmpty ? null : Loaded(_pending(uid), fromCache: true);
    return _withPending(uid, cached);
  }

  Future<Loaded<List<JobApplication>>> fetchAll(String uid) async {
    final l = await fetchAndCache(key: _key(uid), fetch: () => backend.fetchApplications(uid), encode: _encode, decode: _decode);
    if (!l.fromCache) {
      // Drop pending copies that the server now knows about.
      final serverIds = l.data.map((a) => a.id).toSet();
      final stillPending = _pending(uid).where((p) => !serverIds.contains(p.id)).toList();
      await store.write(_pendingKey(uid), _encode(stillPending));
    }
    return _withPending(uid, l);
  }

  /// Submits an application. When offline it is queued and shown as
  /// "waiting to send"; returns the application either way.
  Future<JobApplication> submit(JobApplication app) async {
    try {
      final saved = await backend.submitApplication(app);
      final list = peek(_key(app.userId), _decode)?.data ?? const [];
      await store.write(_key(app.userId), _encode([saved, ...list.where((a) => a.id != saved.id)]));
      return saved;
    } on NetworkException {
      final pending = app.copyWith(pendingSync: true);
      await store.write(_pendingKey(app.userId), _encode([pending, ..._pending(app.userId)]));
      await sync.enqueue('submit_application', app.toJson(includeLocal: false), label: 'Application for ${app.job?.title ?? 'a job'}');
      return pending;
    }
  }

  Future<JobApplication> withdraw(JobApplication app, {String? reason}) async {
    final local = app.copyWith(
      status: ApplicationStatus.withdrawn,
      history: [...app.history, StatusEvent(status: ApplicationStatus.withdrawn, at: DateTime.now(), note: reason)],
    );
    Future<void> writeLocal(JobApplication a) async {
      final list = peek(_key(app.userId), _decode)?.data ?? const [];
      await store.write(_key(app.userId), _encode([for (final x in list) x.id == a.id ? a : x]));
    }

    try {
      final saved = await backend.withdrawApplication(app.id, reason: reason);
      await writeLocal(saved);
      return saved;
    } on NetworkException {
      await writeLocal(local);
      await sync.enqueue('withdraw_application', {'id': app.id, 'reason': reason}, label: 'Withdrawal');
      return local;
    }
  }

  Future<void> _removePending(String id) async {
    for (final key in store.keysWithPrefix('u:').where((k) => k.endsWith(':pending_applications')).toList()) {
      final list = peek(key, _decode)?.data ?? const [];
      await store.write(key, _encode(list.where((a) => a.id != id).toList()));
    }
  }
}
