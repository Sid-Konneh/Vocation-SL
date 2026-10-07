import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../models/models.dart';
import '../providers/core_providers.dart';
import '../providers/session_providers.dart';
import 'data/admin_backend.dart';

/// Injected in main.dart.
final adminBackendProvider = Provider<AdminBackend>((ref) => throw UnimplementedError('Override in main'));

/// The signed-in user's admin role (null = not an admin).
final adminRoleProvider = FutureProvider<AdminRole?>((ref) async {
  final uid = ref.watch(sessionProvider);
  if (uid == null) return null;
  return ref.watch(adminBackendProvider).myRole();
});

// ---- Admin data (always fetched fresh; the dashboard is an online tool) ----------

final adminStatsProvider = FutureProvider.autoDispose<AdminStats>((ref) => ref.watch(adminBackendProvider).stats());
final adminJobsProvider = FutureProvider.autoDispose<List<Job>>((ref) => ref.watch(adminBackendProvider).jobs());
final adminCompaniesProvider = FutureProvider.autoDispose<List<AdminCompany>>((ref) => ref.watch(adminBackendProvider).companies());
final adminUsersProvider = FutureProvider.autoDispose<List<AdminUser>>((ref) => ref.watch(adminBackendProvider).users());
final adminApplicationsProvider =
    FutureProvider.autoDispose<List<JobApplication>>((ref) => ref.watch(adminBackendProvider).applications());
final adminReportsProvider = FutureProvider.autoDispose<List<Report>>((ref) => ref.watch(adminBackendProvider).reports());
final adminAnnouncementsProvider =
    FutureProvider.autoDispose<List<Announcement>>((ref) => ref.watch(adminBackendProvider).announcements());
final adminPagesProvider = FutureProvider.autoDispose<List<SitePage>>((ref) => ref.watch(adminBackendProvider).pages());
final adminSettingsProvider = FutureProvider.autoDispose<PlatformSettings>((ref) => ref.watch(adminBackendProvider).settings());
final adminTeamProvider = FutureProvider.autoDispose<List<AdminMember>>((ref) => ref.watch(adminBackendProvider).team());
final adminActivityProvider = FutureProvider.autoDispose<List<AuditEntry>>((ref) => ref.watch(adminBackendProvider).activity());

/// Runs an admin action, then refreshes whatever it affected (and the
/// dashboard numbers and activity log, which every action changes).
class AdminActions {
  AdminActions(this._ref);
  final Ref _ref;

  AdminBackend get _b => _ref.read(adminBackendProvider);

  Future<void> run(Future<void> Function(AdminBackend b) action, {List<ProviderOrFamily> refresh = const []}) async {
    await action(_b);
    for (final p in [...refresh, adminStatsProvider, adminActivityProvider]) {
      _ref.invalidate(p);
    }
  }
}

final adminActionsProvider = Provider((ref) => AdminActions(ref));

// ---- Public platform content -------------------------------------------------------

final platformSettingsProvider = FutureProvider<PlatformSettings>((ref) async {
  try {
    return await ref.watch(backendProvider).fetchPlatformSettings();
  } catch (_) {
    return const PlatformSettings();
  }
});

final announcementsProvider = FutureProvider<List<Announcement>>((ref) async {
  ref.watch(sessionProvider);
  try {
    return await ref.watch(backendProvider).fetchAnnouncements();
  } catch (_) {
    return const [];
  }
});

final sitePageProvider = FutureProvider.family<SitePage?, String>((ref, slug) => ref.watch(backendProvider).fetchPage(slug));

/// Whether the signed-in account is suspended (false while unknown).
final suspendedProvider = FutureProvider<bool>((ref) async {
  final uid = ref.watch(sessionProvider);
  if (uid == null) return false;
  try {
    return await ref.watch(backendProvider).isSuspended();
  } catch (_) {
    return false;
  }
});
