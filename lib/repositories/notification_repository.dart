import '../core/errors.dart';
import '../data/backend/backend.dart';
import '../models/models.dart';
import 'base.dart';
import 'sync_service.dart';

class NotificationRepository extends CachedRepository {
  NotificationRepository(super.store, this.backend, this.sync) {
    sync.register('mark_read', (p) => backend.markNotificationsRead(p['user_id'] as String, (p['ids'] as List).cast<String>()));
    sync.register('delete_notification', (p) => backend.deleteNotification(p['id'] as String));
  }

  final VocationBackend backend;
  final SyncService sync;

  String _key(String uid) => 'u:$uid:notifications';
  List<AppNotification> _decode(Object? j) => jsonList(j).map(AppNotification.fromJson).toList();
  Object _encode(List<AppNotification> v) => v.map((n) => n.toJson()).toList();

  Loaded<List<AppNotification>>? peekAll(String uid) => peek(_key(uid), _decode);

  Future<Loaded<List<AppNotification>>> fetchAll(String uid) =>
      fetchAndCache(key: _key(uid), fetch: () => backend.fetchNotifications(uid), encode: _encode, decode: _decode);

  Future<void> _writeLocal(String uid, List<AppNotification> list) => store.write(_key(uid), _encode(list));

  /// Marks the given notifications read (all of them when [ids] is empty).
  Future<void> markRead(String uid, List<AppNotification> current, List<String> ids) async {
    final set = ids.toSet();
    await _writeLocal(uid, [for (final n in current) (set.isEmpty || set.contains(n.id)) ? n.copyWith(read: true) : n]);
    try {
      await backend.markNotificationsRead(uid, ids);
    } on NetworkException {
      await sync.enqueue('mark_read', {'user_id': uid, 'ids': ids}, label: 'Mark as read');
    }
  }

  Future<void> delete(String uid, List<AppNotification> current, String id) async {
    await _writeLocal(uid, current.where((n) => n.id != id).toList());
    try {
      await backend.deleteNotification(id);
    } on NetworkException {
      await sync.enqueue('delete_notification', {'id': id}, label: 'Delete notification');
    }
  }
}
