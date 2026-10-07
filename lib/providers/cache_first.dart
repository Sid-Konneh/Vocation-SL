import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../repositories/base.dart';

/// Base for controllers that show cached data immediately, then refresh
/// from the network in the background when the cache is stale.
abstract class CacheFirstNotifier<T> extends AsyncNotifier<Loaded<T>> {
  Loaded<T>? readCache();
  Future<Loaded<T>> fetchRemote();
  bool get cacheIsFresh;

  bool _refreshing = false;

  @override
  Future<Loaded<T>> build() async {
    final cached = readCache();
    if (cached != null) {
      if (!cacheIsFresh) scheduleMicrotask(refresh);
      return cached;
    }
    return fetchRemote();
  }

  /// Fetches fresh data. Keeps showing current data if the refresh fails.
  Future<void> refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final result = await fetchRemote();
      if (ref.mounted) state = AsyncData(result);
    } catch (e, st) {
      if (!ref.mounted) return;
      final current = state.value;
      if (current != null) {
        state = AsyncData(Loaded(current.data,
            syncedAt: current.syncedAt, fromCache: true, error: e is AppException ? e : const ServerException()));
      } else {
        state = AsyncError(e, st);
      }
    } finally {
      _refreshing = false;
    }
  }

  /// Replaces the data locally (after an optimistic write).
  void setData(T data) {
    final current = state.value;
    state = AsyncData(current == null ? Loaded(data, syncedAt: DateTime.now()) : current.withData(data));
  }

  T? get dataOrNull => state.value?.data;
}
