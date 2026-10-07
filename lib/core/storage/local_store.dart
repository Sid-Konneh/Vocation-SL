import 'dart:convert';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../config/app_config.dart';

/// A cached value plus when it was written.
class CacheEntry<T> {
  const CacheEntry(this.data, this.savedAt);
  final T data;
  final DateTime savedAt;

  Duration get age => DateTime.now().difference(savedAt);
  bool isFresh(Duration ttl) => age < ttl;
}

/// Thin wrapper over Hive. Everything is stored as JSON strings so no
/// generated adapters are needed and models stay backend-agnostic.
class LocalStore {
  LocalStore._(this._cache, this._outbox, this._settings, this._demo);

  final Box<String> _cache;
  final Box<String> _outbox;
  final Box<String> _settings;
  final Box<String> _demo;

  /// Opens the boxes. Pass [path] to store data in a specific directory (tests).
  static Future<LocalStore> open({String? path}) async {
    if (path != null) {
      Hive.init(path);
    } else {
      await Hive.initFlutter('vocation_sl');
    }
    final boxes = await Future.wait([
      Hive.openBox<String>('cache'),
      Hive.openBox<String>('outbox'),
      Hive.openBox<String>('settings'),
      Hive.openBox<String>('demo_server'),
    ]);
    final store = LocalStore._(boxes[0], boxes[1], boxes[2], boxes[3]);
    await store._evictExpired();
    return store;
  }

  // ---- Cache ---------------------------------------------------------------

  CacheEntry<Object?>? read(String key) {
    final raw = _cache.get(key);
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return CacheEntry(map['d'], DateTime.parse(map['t'] as String));
    } catch (_) {
      _cache.delete(key);
      return null;
    }
  }

  Future<void> write(String key, Object? data) =>
      _cache.put(key, jsonEncode({'t': DateTime.now().toIso8601String(), 'd': data}));

  Future<void> remove(String key) => _cache.delete(key);

  Iterable<String> keysWithPrefix(String prefix) => _cache.keys.cast<String>().where((k) => k.startsWith(prefix));

  Future<void> clearCache() => _cache.clear();

  Future<void> _evictExpired() async {
    final stale = <String>[];
    for (final key in _cache.keys.cast<String>()) {
      final e = read(key);
      if (e == null || e.age > CacheTtl.maxAge) stale.add(key);
    }
    await _cache.deleteAll(stale);
  }

  // ---- Outbox (pending offline writes) -------------------------------------

  List<Map<String, dynamic>> outboxItems() {
    final items = _outbox.values.map((v) => jsonDecode(v) as Map<String, dynamic>).toList();
    items.sort((a, b) => (a['created_at'] as String).compareTo(b['created_at'] as String));
    return items;
  }

  Future<void> putOutbox(String id, Map<String, dynamic> item) => _outbox.put(id, jsonEncode(item));
  Future<void> removeOutbox(String id) => _outbox.delete(id);
  int get outboxCount => _outbox.length;
  Future<void> clearOutbox() => _outbox.clear();

  // ---- Settings ------------------------------------------------------------

  T? setting<T>(String key) {
    final raw = _settings.get(key);
    return raw == null ? null : jsonDecode(raw) as T?;
  }

  Future<void> setSetting(String key, Object? value) => _settings.put(key, jsonEncode(value));
  Future<void> removeSetting(String key) => _settings.delete(key);

  // ---- Demo backend state ----------------------------------------------------

  Map<String, dynamic>? demoState() {
    final raw = _demo.get('state');
    return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
  }

  Future<void> saveDemoState(Map<String, dynamic> state) => _demo.put('state', jsonEncode(state));
  Future<void> clearDemoState() => _demo.clear();
}
