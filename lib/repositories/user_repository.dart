import 'dart:typed_data';

import '../core/errors.dart';
import '../data/backend/backend.dart';
import '../models/models.dart';
import 'base.dart';
import 'sync_service.dart';

/// Authentication and the signed-in user's profile.
class UserRepository extends CachedRepository {
  UserRepository(super.store, this.backend, this.sync) {
    sync.register('update_user', (p) async {
      await backend.updateUser(AppUser.fromJson(p));
    });
  }

  final VocationBackend backend;
  final SyncService sync;

  String? get currentUserId => backend.currentUserId;
  Stream<String?> get authChanges => backend.authChanges;
  bool get supportsGoogleSignIn => backend.supportsGoogleSignIn;

  Future<void> signInWithGoogle() => backend.signInWithGoogle();
  Stream<void> get passwordRecovery => backend.passwordRecovery;

  Future<void> updatePassword(String password, String confirm) {
    if (password.length < 8) throw const ValidationException('Use at least 8 characters for your password.');
    if (password != confirm) throw const ValidationException('The passwords don\'t match.');
    return backend.updatePassword(password);
  }

  Future<void> sendPasswordReset(String email) {
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim())) {
      throw const ValidationException('Enter the email address you signed up with.');
    }
    return backend.sendPasswordReset(email);
  }
  String _key(String uid) => 'u:$uid:profile';

  Future<String> signIn(String email, String password) {
    if (email.trim().isEmpty || password.isEmpty) {
      throw const ValidationException('Enter your email and password.');
    }
    return backend.signIn(email: email, password: password);
  }

  Future<String> signUp(String name, String email, String password) {
    if (name.trim().length < 2) throw const ValidationException('Enter your full name.');
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email.trim())) {
      throw const ValidationException('Enter a valid email address.');
    }
    if (password.length < 8) throw const ValidationException('Use at least 8 characters for your password.');
    return backend.signUp(fullName: name, email: email, password: password);
  }

  Future<void> signOut() async {
    final uid = currentUserId;
    await backend.signOut();
    if (uid != null) {
      for (final k in store.keysWithPrefix('u:$uid:').toList()) {
        await store.remove(k);
      }
    }
    await store.clearOutbox();
  }

  Loaded<AppUser>? peekProfile(String uid) => peek(_key(uid), _decode);

  Future<Loaded<AppUser>> fetchProfile(String uid) => fetchAndCache(
        key: _key(uid),
        fetch: () => backend.fetchUser(uid),
        encode: (u) => u.toJson(),
        decode: _decode,
      );

  AppUser _decode(Object? j) => AppUser.fromJson(Map<String, dynamic>.from(j as Map));

  /// Saves the profile. Offline edits are kept locally and synced later.
  /// Returns true if the change reached the server now.
  Future<bool> updateProfile(AppUser user) async {
    await store.write(_key(user.id), user.toJson());
    try {
      await backend.updateUser(user);
      return true;
    } on NetworkException {
      await sync.enqueue('update_user', user.toJson(), label: 'Profile update');
      return false;
    }
  }

  Future<String> uploadDocument(String uid, String fileName, Uint8List bytes) =>
      backend.uploadDocument(userId: uid, fileName: fileName, bytes: bytes);
}
