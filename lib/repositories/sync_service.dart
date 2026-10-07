import 'dart:async';

import 'package:uuid/uuid.dart';

import '../core/errors.dart';
import '../core/network/connectivity_service.dart';
import '../core/storage/local_store.dart';

typedef OutboxHandler = Future<void> Function(Map<String, dynamic> payload);

/// Result of replaying queued offline writes.
class SyncReport {
  const SyncReport({this.synced = 0, this.failed = const []});
  final int synced;

  /// Human-readable descriptions of writes the server rejected.
  final List<String> failed;
}

/// Queues writes made while offline and replays them, in order, when the
/// connection returns.
class SyncService {
  SyncService({required this.store, required this.connectivity}) {
    _sub = connectivity.changes.listen((online) {
      if (online) flush();
    });
  }

  final LocalStore store;
  final ConnectivityService connectivity;
  final _handlers = <String, OutboxHandler>{};
  final _rejectHandlers = <String, Future<void> Function(Map<String, dynamic>)>{};
  final _reports = StreamController<SyncReport>.broadcast();
  StreamSubscription<bool>? _sub;
  bool _flushing = false;

  /// Emits after each flush that did something.
  Stream<SyncReport> get reports => _reports.stream;
  int get pendingCount => store.outboxCount;

  void register(String type, OutboxHandler handler, {Future<void> Function(Map<String, dynamic>)? onRejected}) {
    _handlers[type] = handler;
    if (onRejected != null) _rejectHandlers[type] = onRejected;
  }

  Future<void> enqueue(String type, Map<String, dynamic> payload, {String? label}) async {
    final id = const Uuid().v4();
    await store.putOutbox(id, {
      'id': id,
      'type': type,
      'payload': payload,
      'label': label ?? type,
      'created_at': DateTime.now().toIso8601String(),
      'attempts': 0,
    });
  }

  Future<SyncReport> flush() async {
    if (_flushing || !connectivity.isOnline || store.outboxCount == 0) return const SyncReport();
    _flushing = true;
    var synced = 0;
    final failed = <String>[];
    try {
      for (final item in store.outboxItems()) {
        final handler = _handlers[item['type']];
        final payload = Map<String, dynamic>.from(item['payload'] as Map);
        if (handler == null) {
          await store.removeOutbox(item['id'] as String);
          continue;
        }
        try {
          await handler(payload);
          await store.removeOutbox(item['id'] as String);
          synced++;
        } on NetworkException {
          break; // Still offline: keep the rest for later, in order.
        } on AppException catch (e) {
          final attempts = (item['attempts'] as int? ?? 0) + 1;
          final retryable = e is ServerException && attempts < 5;
          if (retryable) {
            await store.putOutbox(item['id'] as String, {...item, 'attempts': attempts});
            break;
          }
          await store.removeOutbox(item['id'] as String);
          await _rejectHandlers[item['type']]?.call(payload);
          failed.add('${item['label']}: ${e.userMessage}');
        }
      }
    } finally {
      _flushing = false;
    }
    final report = SyncReport(synced: synced, failed: failed);
    if (synced > 0 || failed.isNotEmpty) _reports.add(report);
    return report;
  }

  void dispose() {
    _sub?.cancel();
    _reports.close();
  }
}
