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
  bool _again = false;

  /// Bumped by [setData]; a fetch that started before a local write is stale.
  int _writes = 0;

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
  /// A call made while a refresh is running fetches again afterwards, so a
  /// change saved meanwhile (e.g. a company just created) is never missed.
  Future<void> refresh() async {
    if (_refreshing) {
      _again = true;
      return;
    }
    _refreshing = true;
    final writesAtStart = _writes;
    try {
      final result = await fetchRemote();
      // Don't let an older fetch overwrite data saved locally since it began.
      if (ref.mounted && writesAtStart == _writes) state = AsyncData(result);
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
      if (_again && ref.mounted) {
        _again = false;
        scheduleMicrotask(refresh);
      }
    }
  }

  /// Replaces the data locally (after an optimistic write).
  void setData(T data) {
    _writes++;
    final current = state.value;
    state = AsyncData(current == null ? Loaded(data, syncedAt: DateTime.now()) : current.withData(data));
  }

  T? get dataOrNull => state.value?.data;
}
