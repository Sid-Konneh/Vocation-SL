/// Build-time configuration.
///
/// Supabase is enabled by passing both values at build time:
///   flutter run --dart-define=SUPABASE_URL=https://xyz.supabase.co \
///               --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_...
/// Without them the app runs entirely on the built-in demo backend.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');

  static bool get useSupabase => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;

  /// Deep link the mobile apps receive after Google sign-in, email
  /// confirmation and password reset. Must be listed in Supabase
  /// Authentication → URL Configuration → Redirect URLs.
  static const mobileAuthRedirect = 'org.vocationsl.app://login-callback';

  static const appName = 'Vocation SL';
  static const pageSize = 10;
  static const supportEmail = 'support@vocationsl.app';
}

/// How long cached data counts as fresh before a background refresh.
class CacheTtl {
  static const jobs = Duration(minutes: 15);
  static const jobDetail = Duration(hours: 1);
  static const companies = Duration(hours: 12);
  static const user = Duration(hours: 6);
  static const applications = Duration(minutes: 5);
  static const notifications = Duration(minutes: 2);
  static const saved = Duration(minutes: 10);

  /// Cached data older than this is discarded entirely.
  static const maxAge = Duration(days: 14);
}
