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
