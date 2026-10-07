import '../core/errors.dart';
import '../core/storage/local_store.dart';

/// Data plus where it came from. When [error] is set, [data] is the last
/// cached copy and the latest refresh failed (typically because offline).
class Loaded<T> {
  const Loaded(this.data, {this.syncedAt, this.fromCache = false, this.error});

  final T data;
  final DateTime? syncedAt;
  final bool fromCache;
  final AppException? error;

  bool get isOfflineCopy => error != null;
  Loaded<R> map<R>(R Function(T) f) => Loaded(f(data), syncedAt: syncedAt, fromCache: fromCache, error: error);
  Loaded<T> withData(T d) => Loaded(d, syncedAt: syncedAt, fromCache: fromCache, error: error);
}

/// Shared cache-first helpers for repositories.
abstract class CachedRepository {
  CachedRepository(this.store);
  final LocalStore store;

  /// Reads a cached value without touching the network.
  Loaded<T>? peek<T>(String key, T Function(Object? json) decode, {Duration? ttl}) {
    final entry = store.read(key);
    if (entry == null) return null;
    try {
      return Loaded(decode(entry.data), syncedAt: entry.savedAt, fromCache: true);
    } catch (_) {
      store.remove(key);
      return null;
    }
  }

  bool isFresh(String key, Duration ttl) => store.read(key)?.isFresh(ttl) ?? false;

  /// Fetches from the network and caches the result. If the network call
  /// fails with a recoverable error and a cached copy exists, the cached copy
  /// is returned with [Loaded.error] set instead of throwing.
  Future<Loaded<T>> fetchAndCache<T>({
    required String key,
    required Future<T> Function() fetch,
    required Object? Function(T value) encode,
    required T Function(Object? json) decode,
  }) async {
    try {
      final value = await fetch();
      await store.write(key, encode(value));
      return Loaded(value, syncedAt: DateTime.now());
    } on AppException catch (e) {
      if (e is NetworkException || e is ServerException) {
        final cached = peek(key, decode);
        if (cached != null) return Loaded(cached.data, syncedAt: cached.syncedAt, fromCache: true, error: e);
      }
      rethrow;
    }
  }
}

List<Map<String, dynamic>> jsonList(Object? v) =>
    (v as List? ?? const []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
