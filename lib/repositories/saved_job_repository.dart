import '../core/errors.dart';
import '../data/backend/backend.dart';
import '../models/models.dart';
import 'base.dart';
import 'sync_service.dart';

/// Saved jobs and saved searches (job alerts).
class SavedJobRepository extends CachedRepository {
  SavedJobRepository(super.store, this.backend, this.sync) {
    sync.register('save_job', (p) => backend.saveJob(SavedJob.fromJson(p)));
    sync.register('unsave_job', (p) => backend.unsaveJob(p['user_id'] as String, p['job_id'] as String));
    sync.register('upsert_alert', (p) async => backend.upsertAlert(JobAlert.fromJson(p)));
    sync.register('delete_alert', (p) => backend.deleteAlert(p['id'] as String));
  }

  final VocationBackend backend;
  final SyncService sync;

  String _savedKey(String uid) => 'u:$uid:saved';
  String _alertsKey(String uid) => 'u:$uid:alerts';

  List<SavedJob> _decodeSaved(Object? j) => jsonList(j).map((m) {
        final s = SavedJob.fromJson(m);
        return m['job'] is Map ? s.withJob(Job.fromJson(Map<String, dynamic>.from(m['job'] as Map))) : s;
      }).toList();

  Object _encodeSaved(List<SavedJob> v) => v.map((s) => {...s.toJson(), if (s.job != null) 'job': s.job!.toJson()}).toList();

  List<JobAlert> _decodeAlerts(Object? j) => jsonList(j).map(JobAlert.fromJson).toList();
  Object _encodeAlerts(List<JobAlert> v) => v.map((a) => a.toJson()).toList();

  // ---- Saved jobs ------------------------------------------------------------

  Loaded<List<SavedJob>>? peekSaved(String uid) => peek(_savedKey(uid), _decodeSaved);

  Future<Loaded<List<SavedJob>>> fetchSaved(String uid) =>
      fetchAndCache(key: _savedKey(uid), fetch: () => backend.fetchSavedJobs(uid), encode: _encodeSaved, decode: _decodeSaved);

  Future<void> save(String uid, Job job, List<SavedJob> current) async {
    final s = SavedJob(jobId: job.id, userId: uid, savedAt: DateTime.now(), job: job);
    await store.write(_savedKey(uid), _encodeSaved([s, ...current.where((x) => x.jobId != job.id)]));
    try {
      await backend.saveJob(s);
    } on NetworkException {
      await sync.enqueue('save_job', s.toJson(), label: 'Save job');
    }
  }

  Future<void> unsave(String uid, String jobId, List<SavedJob> current) async {
    await store.write(_savedKey(uid), _encodeSaved(current.where((x) => x.jobId != jobId).toList()));
    try {
      await backend.unsaveJob(uid, jobId);
    } on NetworkException {
      await sync.enqueue('unsave_job', {'user_id': uid, 'job_id': jobId}, label: 'Remove saved job');
    }
  }

  // ---- Saved searches --------------------------------------------------------

  Loaded<List<JobAlert>>? peekAlerts(String uid) => peek(_alertsKey(uid), _decodeAlerts);

  Future<Loaded<List<JobAlert>>> fetchAlerts(String uid) =>
      fetchAndCache(key: _alertsKey(uid), fetch: () => backend.fetchAlerts(uid), encode: _encodeAlerts, decode: _decodeAlerts);

  Future<void> upsertAlert(JobAlert alert, List<JobAlert> current) async {
    final exists = current.any((a) => a.id == alert.id);
    await store.write(
        _alertsKey(alert.userId), _encodeAlerts(exists ? [for (final a in current) a.id == alert.id ? alert : a] : [alert, ...current]));
    try {
      await backend.upsertAlert(alert);
    } on NetworkException {
      await sync.enqueue('upsert_alert', alert.toJson(), label: 'Saved search');
    }
  }

  Future<void> deleteAlert(String uid, String id, List<JobAlert> current) async {
    await store.write(_alertsKey(uid), _encodeAlerts(current.where((a) => a.id != id).toList()));
    try {
      await backend.deleteAlert(id);
    } on NetworkException {
      await sync.enqueue('delete_alert', {'id': id}, label: 'Delete saved search');
    }
  }
}
