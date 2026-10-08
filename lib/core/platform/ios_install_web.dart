import 'dart:js_interop';

import 'package:web/web.dart' as web;

@JS('navigator.standalone')
external JSBoolean? get _iosStandalone;

/// True in Safari (or another browser) on an iPhone or iPad, when the app
/// hasn't been added to the home screen yet.
bool get canSuggestIosInstall {
  try {
    final ua = web.window.navigator.userAgent;
    final maxTouch = web.window.navigator.maxTouchPoints;
    // iPadOS reports itself as a Mac; touch support tells them apart.
    final isIos = RegExp(r'iPhone|iPad|iPod').hasMatch(ua) || (ua.contains('Macintosh') && maxTouch > 1);
    if (!isIos) return false;
    final installed = web.window.matchMedia('(display-mode: standalone)').matches || (_iosStandalone?.toDart ?? false);
    return !installed;
  } catch (_) {
    return false;
  }
}
