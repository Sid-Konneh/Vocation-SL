import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dev_settings.dart';
import '../core/network/connectivity_service.dart';
import '../core/storage/local_store.dart';
import '../data/backend/backend.dart';
import '../data/backend/demo_backend.dart';
import '../repositories/application_repository.dart';
import '../repositories/job_repository.dart';
import '../repositories/notification_repository.dart';
import '../repositories/saved_job_repository.dart';
import '../repositories/sync_service.dart';
import '../repositories/user_repository.dart';
import '../services/file_service.dart';
import '../services/share_service.dart';

// These three are created in main() and injected with overrides.
final localStoreProvider = Provider<LocalStore>((ref) => throw UnimplementedError('Override in main'));
final connectivityServiceProvider = Provider<ConnectivityService>((ref) => throw UnimplementedError('Override in main'));
final backendProvider = Provider<VocationBackend>((ref) => throw UnimplementedError('Override in main'));

final syncServiceProvider = Provider<SyncService>((ref) {
  final s = SyncService(store: ref.watch(localStoreProvider), connectivity: ref.watch(connectivityServiceProvider));
  ref.onDispose(s.dispose);
  return s;
});

final jobRepositoryProvider = Provider((ref) => JobRepository(ref.watch(localStoreProvider), ref.watch(backendProvider)));
final userRepositoryProvider =
    Provider((ref) => UserRepository(ref.watch(localStoreProvider), ref.watch(backendProvider), ref.watch(syncServiceProvider)));
final applicationRepositoryProvider =
    Provider((ref) => ApplicationRepository(ref.watch(localStoreProvider), ref.watch(backendProvider), ref.watch(syncServiceProvider)));
final notificationRepositoryProvider =
    Provider((ref) => NotificationRepository(ref.watch(localStoreProvider), ref.watch(backendProvider), ref.watch(syncServiceProvider)));
final savedJobRepositoryProvider =
    Provider((ref) => SavedJobRepository(ref.watch(localStoreProvider), ref.watch(backendProvider), ref.watch(syncServiceProvider)));

final fileServiceProvider = Provider((ref) => FileService());
final shareServiceProvider = Provider((ref) => ShareService());

/// Whether the app is online (device connectivity and the simulator switch).
class OnlineNotifier extends Notifier<bool> {
  StreamSubscription<bool>? _sub;

  @override
  bool build() {
    final service = ref.watch(connectivityServiceProvider);
    _sub?.cancel();
    _sub = service.changes.listen((v) => state = v);
    ref.onDispose(() => _sub?.cancel());
    return service.isOnline;
  }
}

final onlineProvider = NotifierProvider<OnlineNotifier, bool>(OnlineNotifier.new);

/// Developer switches for testing offline mode and failures.
class DevSettingsNotifier extends Notifier<DevSettings> {
  @override
  DevSettings build() => DevSettings.load(ref.watch(localStoreProvider));

  Future<void> update(DevSettings s) async {
    state = s;
    ref.read(connectivityServiceProvider).simulateOffline = s.simulateOffline;
    await s.save(ref.read(localStoreProvider));
  }
}

final devSettingsProvider = NotifierProvider<DevSettingsNotifier, DevSettings>(DevSettingsNotifier.new);

/// Number of writes waiting to sync. Refresh with ref.invalidate.
final pendingSyncCountProvider = Provider<int>((ref) {
  ref.watch(onlineProvider);
  return ref.watch(syncServiceProvider).pendingCount;
});

bool isDemoBackend(VocationBackend b) => b is DemoBackend;
