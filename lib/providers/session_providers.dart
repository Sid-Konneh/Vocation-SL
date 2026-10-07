import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../models/models.dart';
import '../repositories/base.dart';
import 'cache_first.dart';
import 'core_providers.dart';

/// The signed-in user's id, or null when signed out.
class SessionNotifier extends Notifier<String?> {
  StreamSubscription<String?>? _sub;

  @override
  String? build() {
    final repo = ref.watch(userRepositoryProvider);
    // Sessions can start or end outside a direct call: returning from
    // Google sign-in, an email link, or an expired refresh token.
    _sub?.cancel();
    _sub = repo.authChanges.listen((uid) {
      if (uid != state) state = uid;
    });
    ref.onDispose(() => _sub?.cancel());
    return repo.currentUserId;
  }

  Future<void> signInWithGoogle() => ref.read(userRepositoryProvider).signInWithGoogle();

  Future<void> signIn(String email, String password) async {
    state = await ref.read(userRepositoryProvider).signIn(email, password);
  }

  Future<void> signUp(String name, String email, String password) async {
    state = await ref.read(userRepositoryProvider).signUp(name, email, password);
  }

  Future<void> signOut() async {
    await ref.read(userRepositoryProvider).signOut();
    state = null;
  }
}

final sessionProvider = NotifierProvider<SessionNotifier, String?>(SessionNotifier.new);

/// The signed-in user's role (job seeker or employer), or null until chosen.
///
/// The login screen records the user's intent ("Find a job" / "Hire talent")
/// before sign-in, so it survives a Google redirect; it is applied here the
/// first time a user without a role signs in.
class RoleNotifier extends Notifier<UserRole?> {
  static const _pendingKey = 'pending_role';

  @override
  UserRole? build() {
    final uid = ref.watch(sessionProvider);
    if (uid == null) return null;
    // The choice made on the login screen wins for this sign-in, so
    // "Find a job" always opens the job seeker side and "Hire talent" the
    // employer side, even if the account last used the other one.
    final store = ref.read(localStoreProvider);
    final pending = store.setting<String>(_pendingKey);
    final intent = UserRole.values.where((r) => r.name == pending).firstOrNull;
    if (intent != null) {
      Future.microtask(() async {
        await store.removeSetting(_pendingKey);
        await choose(intent);
      });
      return intent;
    }
    return ref.watch(backendProvider).currentRole;
  }

  /// Remembers the role picked on the login screen. It is applied once the
  /// session starts (also after a Google redirect) and then cleared.
  Future<void> setIntent(UserRole role) => ref.read(localStoreProvider).setSetting(_pendingKey, role.name);

  Future<void> choose(UserRole role) async {
    state = role;
    // Pre-selects the same side on the login screen next time.
    await ref.read(localStoreProvider).setSetting('last_role', role.name);
    try {
      await ref.read(backendProvider).setRole(role);
    } catch (_) {
      // Saved locally; it is re-applied on next sign-in.
    }
  }
}

final roleProvider = NotifierProvider<RoleNotifier, UserRole?>(RoleNotifier.new);

String requireUid(Ref ref) {
  final uid = ref.watch(sessionProvider);
  if (uid == null) throw StateError('Not signed in');
  return uid;
}

/// The signed-in user's profile, cache-first.
class ProfileController extends CacheFirstNotifier<AppUser> {
  late String _uid;

  @override
  Future<Loaded<AppUser>> build() {
    _uid = requireUid(ref);
    return super.build();
  }

  @override
  Loaded<AppUser>? readCache() => ref.read(userRepositoryProvider).peekProfile(_uid);

  @override
  bool get cacheIsFresh => ref.read(userRepositoryProvider).isFresh('u:$_uid:profile', CacheTtl.user);

  @override
  Future<Loaded<AppUser>> fetchRemote() => ref.read(userRepositoryProvider).fetchProfile(_uid);

  /// Saves changes. Returns true if they reached the server immediately.
  Future<bool> save(AppUser user) async {
    setData(user);
    return ref.read(userRepositoryProvider).updateProfile(user);
  }
}

final profileProvider = AsyncNotifierProvider<ProfileController, Loaded<AppUser>>(ProfileController.new);
