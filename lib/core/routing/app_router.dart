import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/applications/application_detail_screen.dart';
import '../../features/applications/applications_screen.dart';
import '../../features/apply/apply_flow_screen.dart';
import '../../features/apply/apply_success_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/jobs/company_screen.dart';
import '../../features/jobs/home_screen.dart';
import '../../features/jobs/job_details_screen.dart';
import '../../features/jobs/search_screen.dart';
import '../../features/notifications/notification_settings_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/profile/change_password_screen.dart';
import '../../features/profile/edit_profile_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/profile/settings_screen.dart';
import '../../features/saved/saved_screen.dart';
import '../../features/shell/home_shell.dart';
import '../../features/splash/splash_screen.dart';
import '../../models/models.dart';
import '../../providers/session_providers.dart';

final rootNavigatorKey = GlobalKey<NavigatorState>();

/// Fade + slight upward slide for pushed pages.
CustomTransitionPage<void> _page(GoRouterState state, Widget child) => CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 280),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      transitionsBuilder: (context, animation, secondary, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.04), end: Offset.zero).animate(curved),
            child: child,
          ),
        );
      },
    );

final routerProvider = Provider<GoRouter>((ref) {
  final auth = ValueNotifier<String?>(ref.read(sessionProvider));
  ref.listen(sessionProvider, (_, next) => auth.value = next);
  ref.onDispose(auth.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: auth,
    redirect: (context, state) {
      final signedIn = auth.value != null;
      final loc = state.matchedLocation;
      if (loc == '/') return null; // splash decides
      if (!signedIn && loc != '/login') return '/login';
      if (signedIn && loc == '/login') return '/jobs';
      return null;
    },
    routes: [
      GoRoute(path: '/', pageBuilder: (c, s) => _page(s, const SplashScreen())),
      GoRoute(path: '/login', pageBuilder: (c, s) => _page(s, const LoginScreen())),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/jobs', builder: (c, s) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/saved', builder: (c, s) => const SavedScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/applications', builder: (c, s) => const ApplicationsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/alerts', builder: (c, s) => const NotificationsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/profile', builder: (c, s) => const ProfileScreen())]),
        ],
      ),
      GoRoute(
        path: '/search',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (c, s) => _page(s, SearchScreen(initialFilter: s.extra is JobFilter ? s.extra as JobFilter : null)),
      ),
      GoRoute(
        path: '/job/:id',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (c, s) => _page(s, JobDetailsScreen(jobId: s.pathParameters['id']!)),
        routes: [
          GoRoute(
            path: 'apply',
            parentNavigatorKey: rootNavigatorKey,
            pageBuilder: (c, s) => _page(s, ApplyFlowScreen(jobId: s.pathParameters['id']!)),
          ),
        ],
      ),
      GoRoute(
        path: '/applied/:appId',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (c, s) => _page(s, ApplySuccessScreen(applicationId: s.pathParameters['appId']!)),
      ),
      GoRoute(
        path: '/application/:id',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (c, s) => _page(s, ApplicationDetailScreen(applicationId: s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/company/:id',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (c, s) => _page(s, CompanyScreen(companyId: s.pathParameters['id']!)),
      ),
      GoRoute(
        path: '/profile/edit',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (c, s) => _page(s, EditProfileScreen(section: s.uri.queryParameters['section'])),
      ),
      GoRoute(path: '/settings', parentNavigatorKey: rootNavigatorKey, pageBuilder: (c, s) => _page(s, const SettingsScreen())),
      GoRoute(
        path: '/settings/password',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (c, s) => _page(s, ChangePasswordScreen(fromReset: s.uri.queryParameters['reset'] == '1')),
      ),
      GoRoute(
        path: '/settings/notifications',
        parentNavigatorKey: rootNavigatorKey,
        pageBuilder: (c, s) => _page(s, const NotificationSettingsScreen()),
      ),
    ],
  );
});
