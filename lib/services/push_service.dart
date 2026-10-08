import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as sb;

import '../core/config/app_config.dart';
import '../firebase_options.dart';

enum PushPermission { unsupported, notAsked, granted, denied }

/// Push alerts through Firebase Cloud Messaging, on Android and the web.
///
/// The device's FCM token is stored in Supabase (push_tokens). The database
/// sends every new alert to the "push" Edge Function, which delivers it even
/// when the app or browser tab is closed. Tapping an alert opens [taps].
class PushService {
  PushService._(this._client);
  final sb.SupabaseClient _client;

  final _taps = StreamController<String>.broadcast();
  final _foreground = StreamController<RemoteMessage>.broadcast();
  String? _token;

  /// Routes to open when the user taps an alert (e.g. /alerts).
  Stream<String> get taps => _taps.stream;

  /// Alerts that arrive while the app is open on screen.
  Stream<RemoteMessage> get foreground => _foreground.stream;

  /// Sets up Firebase, or returns null when push isn't configured or the
  /// platform isn't supported (iOS needs an Apple developer account first).
  static Future<PushService?> start(sb.SupabaseClient client) async {
    if (!AppConfig.useSupabase) return null;
    final FirebaseOptions options;
    try {
      options = DefaultFirebaseOptions.currentPlatform;
    } on UnsupportedError {
      return null; // iOS and desktop aren't set up for push
    }
    if (options.apiKey.isEmpty || options.appId.isEmpty) return null; // flutterfire configure not run yet
    try {
      await Firebase.initializeApp(options: options);
    } catch (e) {
      debugPrint('Push disabled: $e');
      return null;
    }    final s = PushService._(client);
    s._listen();
    return s;
  }

  FirebaseMessaging get _fm => FirebaseMessaging.instance;

  void _listen() {
    FirebaseMessaging.onMessage.listen(_foreground.add);
    FirebaseMessaging.onMessageOpenedApp.listen(_opened);
    // The app was started by tapping an alert.
    unawaited(_fm.getInitialMessage().then((m) {
      if (m != null) _opened(m);
    }));
    _fm.onTokenRefresh.listen((t) {
      _token = t;
      unawaited(_register(t));
    });
  }

  void _opened(RemoteMessage m) {
    final route = m.data['route'];
    _taps.add(route is String && route.startsWith('/') ? route : '/alerts');
  }

  Future<PushPermission> permission() async {
    final s = await _fm.getNotificationSettings();
    return switch (s.authorizationStatus) {
      AuthorizationStatus.authorized || AuthorizationStatus.provisional => PushPermission.granted,
      AuthorizationStatus.denied || AuthorizationStatus.deniedPermanently => PushPermission.denied,
      AuthorizationStatus.notDetermined => PushPermission.notAsked,
    };
  }

  /// Asks to show alerts (the browser or Android permission prompt), then
  /// registers this device. Returns the resulting permission.
  Future<PushPermission> enable() async {
    await _fm.requestPermission(alert: true, badge: true, sound: true);
    final p = await permission();
    if (p == PushPermission.granted) await sync();
    return p;
  }

  /// Registers this device for the signed-in user, if alerts are allowed.
  Future<void> sync() async {
    if (_client.auth.currentUser == null) return;
    if (await permission() != PushPermission.granted) return;
    try {
      final t = await _fm.getToken(vapidKey: kIsWeb && AppConfig.firebaseVapidKey.isNotEmpty ? AppConfig.firebaseVapidKey : null);
      if (t == null) return;
      _token = t;
      await _register(t);
    } catch (e) {
      debugPrint('Push token not available: $e');
    }
  }

  Future<void> _register(String token) async {
    if (_client.auth.currentUser == null) return;
    try {
      await _client.rpc('register_push_token', params: {'p_token': token, 'p_platform': kIsWeb ? 'web' : 'android'});
    } catch (e) {
      debugPrint('Push token not saved: $e');
    }
  }

  /// Stops alerts for this device. Call before signing out. Never takes
  /// more than a few seconds, so sign-out can't get stuck here.
  Future<void> unregister() async {
    final t = _token;
    _token = null;
    if (t == null) return;
    try {
      await _client.rpc('unregister_push_token', params: {'p_token': t}).timeout(const Duration(seconds: 4));
    } catch (_) {}
    // Deleting the browser/phone token can be slow; don't wait for it.
    unawaited(_fm.deleteToken().catchError((_) {}));
  }
}
