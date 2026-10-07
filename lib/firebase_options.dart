// Placeholder until you run:
//   flutterfire configure --project=vocation-sl-8c645 --platforms=android,web
// which replaces this file with your Firebase project's settings.
// While the values are empty, push alerts stay switched off.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError('Push alerts are set up for Android and the web only.');
    }
  }

  static const FirebaseOptions web = FirebaseOptions(apiKey: '', appId: '', messagingSenderId: '', projectId: '');
  static const FirebaseOptions android = FirebaseOptions(apiKey: '', appId: '', messagingSenderId: '', projectId: '');
}
