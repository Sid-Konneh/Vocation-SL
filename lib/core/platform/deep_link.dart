// Shared links use plain paths (app.vocationsl.com/job/123) so the Android
// app can open them; the web app routes by the #fragment.
export 'deep_link_stub.dart' if (dart.library.js_interop) 'deep_link_web.dart';
