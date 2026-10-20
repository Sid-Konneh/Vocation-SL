import 'package:web/web.dart' as web;

/// The web app routes by the #fragment, so a shared link such as
/// app.vocationsl.com/job/123 is rewritten to app.vocationsl.com/#/job/123
/// before the app starts. Only job and referral links are moved.
void movePathLinkToFragment() {
  try {
    final loc = web.window.location;
    final path = loc.pathname;
    final hasRoute = loc.hash.length > 2;
    if (hasRoute || !RegExp(r'^/(job|r)/[^/]+/?$').hasMatch(path)) return;
    final clean = path.endsWith('/') ? path.substring(0, path.length - 1) : path;
    web.window.history.replaceState(null, '', '/${loc.search}#$clean');
  } catch (_) {
    // Leave the address as it is; the app opens on its home screen.
  }
}
