import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/config/app_config.dart';
import '../models/models.dart';
import '../repositories/base.dart';
import 'cache_first.dart';
import 'core_providers.dart';
import 'session_providers.dart';

// ---- Applications --------------------------------------------------------------

class ApplicationsController extends CacheFirstNotifier<List<JobApplication>> {
  late String _uid;

  @override
  Future<Loaded<List<JobApplication>>> build() {
    _uid = requireUid(ref);
    return super.build();
  }

  @override
  Loaded<List<JobApplication>>? readCache() => ref.read(applicationRepositoryProvider).peekAll(_uid);
  @override
  bool get cacheIsFresh => ref.read(applicationRepositoryProvider).isFresh('u:$_uid:applications', CacheTtl.applications);
  @override
  Future<Loaded<List<JobApplication>>> fetchRemote() => ref.read(applicationRepositoryProvider).fetchAll(_uid);

  Future<JobApplication> submit(JobApplication app) async {
    final result = await ref.read(applicationRepositoryProvider).submit(app);
    setData([result, ...?dataOrNull?.where((a) => a.id != result.id)]);
    ref.invalidate(pendingSyncCountProvider);
    // The backend may have created a "submitted" notification.
    unawaited(ref.read(notificationsProvider.notifier).refresh());
    return result;
  }

  Future<JobApplication> withdraw(JobApplication app, {String? reason}) async {
    final result = await ref.read(applicationRepositoryProvider).withdraw(app, reason: reason);
    setData([for (final a in dataOrNull ?? <JobApplication>[]) a.id == result.id ? result.copyWith(job: () => a.job) : a]);
    ref.invalidate(pendingSyncCountProvider);
    return result;
  }
}

final applicationsProvider =
    AsyncNotifierProvider<ApplicationsController, Loaded<List<JobApplication>>>(ApplicationsController.new);

/// The user's live (not withdrawn) application for a job, if any.
final applicationForJobProvider = Provider.family<JobApplication?, String>((ref, jobId) {
  final apps = ref.watch(applicationsProvider).value?.data ?? const [];
  for (final a in apps) {
    if (a.jobId == jobId && a.status != ApplicationStatus.withdrawn) return a;
  }
  return null;
});

final applicationByIdProvider = Provider.family<JobApplication?, String>((ref, id) {
  final apps = ref.watch(applicationsProvider).value?.data ?? const [];
  for (final a in apps) {
    if (a.id == id) return a;
  }
  return null;
});

// ---- Notifications --------------------------------------------------------------

class NotificationsController extends CacheFirstNotifier<List<AppNotification>> {
  late String _uid;
  Timer? _poll;

  @override
  Future<Loaded<List<AppNotification>>> build() {
    _uid = requireUid(ref);
    // Poll while signed in. A realtime backend can replace this with a subscription.
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _pollOnce());
    ref.onDispose(() => _poll?.cancel());
    return super.build();
  }

  Future<void> _pollOnce() async {
    if (!ref.read(onlineProvider)) return;
    final before = dataOrNull?.length ?? 0;
    await refresh();
    final after = dataOrNull?.length ?? 0;
    // New notifications often mean an application status changed.
    if (after != before && ref.mounted) unawaited(ref.read(applicationsProvider.notifier).refresh());
  }

  @override
  Loaded<List<AppNotification>>? readCache() => ref.read(notificationRepositoryProvider).peekAll(_uid);
  @override
  bool get cacheIsFresh => ref.read(notificationRepositoryProvider).isFresh('u:$_uid:notifications', CacheTtl.notifications);
  @override
  Future<Loaded<List<AppNotification>>> fetchRemote() => ref.read(notificationRepositoryProvider).fetchAll(_uid);

  Future<void> markRead(List<String> ids) async {
    final current = dataOrNull ?? const [];
    final set = ids.toSet();
    setData([for (final n in current) (set.isEmpty || set.contains(n.id)) ? n.copyWith(read: true) : n]);
    await ref.read(notificationRepositoryProvider).markRead(_uid, current, ids);
    ref.invalidate(pendingSyncCountProvider);
  }

  Future<void> markAllRead() => markRead(const []);

  Future<void> delete(String id) async {
    final current = dataOrNull ?? const [];
    setData(current.where((n) => n.id != id).toList());
    await ref.read(notificationRepositoryProvider).delete(_uid, current, id);
  }
}

final notificationsProvider =
    AsyncNotifierProvider<NotificationsController, Loaded<List<AppNotification>>>(NotificationsController.new);

final unreadCountProvider = Provider<int>((ref) {
  final list = ref.watch(notificationsProvider).value?.data ?? const [];
  return list.where((n) => !n.read).length;
});

// ---- Saved jobs -----------------------------------------------------------------

class SavedJobsController extends CacheFirstNotifier<List<SavedJob>> {
  late String _uid;

  @override
  Future<Loaded<List<SavedJob>>> build() {
    _uid = requireUid(ref);
    return super.build();
  }

  @override
  Loaded<List<SavedJob>>? readCache() => ref.read(savedJobRepositoryProvider).peekSaved(_uid);
  @override
  bool get cacheIsFresh => ref.read(savedJobRepositoryProvider).isFresh('u:$_uid:saved', CacheTtl.saved);
  @override
  Future<Loaded<List<SavedJob>>> fetchRemote() => ref.read(savedJobRepositoryProvider).fetchSaved(_uid);

  bool isSaved(String jobId) => dataOrNull?.any((s) => s.jobId == jobId) ?? false;

  /// Saves or unsaves. Returns the new saved state.
  Future<bool> toggle(Job job) async {
    final current = dataOrNull ?? const <SavedJob>[];
    final repo = ref.read(savedJobRepositoryProvider);
    if (isSaved(job.id)) {
      setData(current.where((s) => s.jobId != job.id).toList());
      await repo.unsave(_uid, job.id, current);
      ref.invalidate(pendingSyncCountProvider);
      return false;
    }
    setData([SavedJob(jobId: job.id, userId: _uid, savedAt: DateTime.now(), job: job), ...current]);
    await repo.save(_uid, job, current);
    ref.invalidate(pendingSyncCountProvider);
    return true;
  }
}

final savedJobsProvider = AsyncNotifierProvider<SavedJobsController, Loaded<List<SavedJob>>>(SavedJobsController.new);

final isJobSavedProvider = Provider.family<bool, String>((ref, jobId) {
  final list = ref.watch(savedJobsProvider).value?.data ?? const [];
  return list.any((s) => s.jobId == jobId);
});

// ---- Saved searches ---------------------------------------------------------------

class AlertsController extends CacheFirstNotifier<List<JobAlert>> {
  late String _uid;

  @override
  Future<Loaded<List<JobAlert>>> build() {
    _uid = requireUid(ref);
    return super.build();
  }

  @override
  Loaded<List<JobAlert>>? readCache() => ref.read(savedJobRepositoryProvider).peekAlerts(_uid);
  @override
  bool get cacheIsFresh => ref.read(savedJobRepositoryProvider).isFresh('u:$_uid:alerts', CacheTtl.saved);
  @override
  Future<Loaded<List<JobAlert>>> fetchRemote() => ref.read(savedJobRepositoryProvider).fetchAlerts(_uid);

  Future<JobAlert> create(String name, JobFilter filter, AlertFrequency frequency) async {
    final alert = JobAlert(
      id: const Uuid().v4(),
      userId: _uid,
      name: name.trim().isEmpty ? filter.summary : name.trim(),
      filter: filter,
      createdAt: DateTime.now(),
      frequency: frequency,
    );
    final current = dataOrNull ?? const <JobAlert>[];
    setData([alert, ...current]);
    await ref.read(savedJobRepositoryProvider).upsertAlert(alert, current);
    ref.invalidate(pendingSyncCountProvider);
    unawaited(ref.read(notificationsProvider.notifier).refresh());
    return alert;
  }

  Future<void> updateAlert(JobAlert alert) async {
    final current = dataOrNull ?? const <JobAlert>[];
    setData([for (final a in current) a.id == alert.id ? alert : a]);
    await ref.read(savedJobRepositoryProvider).upsertAlert(alert, current);
  }

  Future<void> delete(String id) async {
    final current = dataOrNull ?? const <JobAlert>[];
    setData(current.where((a) => a.id != id).toList());
    await ref.read(savedJobRepositoryProvider).deleteAlert(_uid, id, current);
  }
}

final alertsProvider = AsyncNotifierProvider<AlertsController, Loaded<List<JobAlert>>>(AlertsController.new);
