// Firebase settings for project vocation-sl-8c645 (Firebase → Project settings).
// These identify the project; they are not secrets.
// Android app: org.vocationsl.vocation_sl.
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

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBqdYjDoxDLVccK3g7Fu1g5a3Is6jWNcRQ',
    appId: '1:598626797751:web:1316cea75731fea3e7a532',
    messagingSenderId: '598626797751',
    projectId: 'vocation-sl-8c645',
    authDomain: 'vocation-sl-8c645.firebaseapp.com',
    storageBucket: 'vocation-sl-8c645.firebasestorage.app',
    measurementId: 'G-EN9V4XMSL7',
  );
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCULDOY6zsa1CvCDvv-0Pw_Zr4pzPq829g',
    appId: '1:598626797751:android:2b5e9882120bdb6fe7a532',
    messagingSenderId: '598626797751',
    projectId: 'vocation-sl-8c645',
    storageBucket: 'vocation-sl-8c645.firebasestorage.app',
  );
}
