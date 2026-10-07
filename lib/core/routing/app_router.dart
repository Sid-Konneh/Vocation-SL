import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../admin/admin_providers.dart';
import '../../admin/admin_shell.dart';
import '../../admin/features/moderation.dart';
import '../../admin/features/overview_insights.dart';
import '../../admin/features/people.dart';
import '../../admin/features/platform.dart';
import '../../employer/employer_shell.dart';
import '../../employer/features/candidates/candidate_detail_screen.dart';
import '../../employer/features/candidates/candidates_screen.dart';
import '../../employer/features/company/company_screens.dart';
import '../../employer/features/dashboard/dashboard_screens.dart';
import '../../employer/features/jobs/job_editor_screen.dart';
import '../../employer/features/jobs/my_jobs_screen.dart';
import '../../features/about/about_screen.dart';
import '../../features/about/site_page_screen.dart';
import '../../features/applications/application_detail_screen.dart';
import '../../features/applications/applications_screen.dart';
import '../../features/apply/apply_flow_screen.dart';
import '../../features/apply/apply_success_screen.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/role_choice_screen.dart';
import '../../features/auth/suspended_screen.dart';
import '../../features/jobs/company_screen.dart';
import '../../features/jobs/home_screen.dart';
import '../../features/jobs/job_details_screen.dart';
import '../../features/jobs/search_screen.dart';
import '../../features/notifications/notification_settings_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/profile/change_password_screen.dart';
import '../../features/profile/delete_account_screen.dart';
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

GoRoute _pushed(String path, Widget Function(GoRouterState s) build, {List<RouteBase> routes = const []}) => GoRoute(
      path: path,
      parentNavigatorKey: rootNavigatorKey,
      pageBuilder: (c, s) => _page(s, build(s)),
      routes: routes,
    );

/// Pages both kinds of user can open.
const _shared = ['/about', '/settings/password', '/choose-role', '/account/delete', '/pages/', '/suspended', '/admin'];

/// Where each role lands after signing in.
String homeFor(UserRole? role) => switch (role) {
      UserRole.employer => '/employer/dashboard',
      UserRole.seeker => '/jobs',
      null => '/choose-role',
    };

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run redirects whenever the session or role changes.
  final refresh = ValueNotifier<int>(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.listen(roleProvider, (_, _) => refresh.value++);
  ref.listen(suspendedProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final signedIn = ref.read(sessionProvider) != null;
      final role = ref.read(roleProvider);
      final loc = state.matchedLocation;
      if (loc == '/') return null; // splash decides
      if (!signedIn) return loc == '/login' ? null : '/login';
      if (loc == '/login') return homeFor(role);
      final suspended = ref.read(suspendedProvider).value ?? false;
      if (suspended && !loc.startsWith('/suspended') && !loc.startsWith('/pages/') && !loc.startsWith('/account/delete')) return '/suspended';
      if (!suspended && loc.startsWith('/suspended')) return homeFor(role);
      if (_shared.any(loc.startsWith)) return null;
      if (role == null) return '/choose-role';
      final inEmployer = loc.startsWith('/employer');
      if (role == UserRole.employer && !inEmployer) return homeFor(role);
      if (role == UserRole.seeker && inEmployer) return homeFor(role);
      return null;
    },
    routes: [
      GoRoute(path: '/', pageBuilder: (c, s) => _page(s, const SplashScreen())),
      GoRoute(path: '/login', pageBuilder: (c, s) => _page(s, const LoginScreen())),
      GoRoute(path: '/choose-role', pageBuilder: (c, s) => _page(s, const RoleChoiceScreen())),

      // ---- Job seeker -------------------------------------------------------
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
      _pushed('/search', (s) => SearchScreen(initialFilter: s.extra is JobFilter ? s.extra as JobFilter : null)),
      _pushed('/job/:id', (s) => JobDetailsScreen(jobId: s.pathParameters['id']!), routes: [
        GoRoute(
          path: 'apply',
          parentNavigatorKey: rootNavigatorKey,
          pageBuilder: (c, s) => _page(s, ApplyFlowScreen(jobId: s.pathParameters['id']!)),
        ),
      ]),
      _pushed('/applied/:appId', (s) => ApplySuccessScreen(applicationId: s.pathParameters['appId']!)),
      _pushed('/application/:id', (s) => ApplicationDetailScreen(applicationId: s.pathParameters['id']!)),
      _pushed('/company/:id', (s) => CompanyScreen(companyId: s.pathParameters['id']!)),
      _pushed('/profile/edit', (s) => EditProfileScreen(section: s.uri.queryParameters['section'])),
      _pushed('/settings', (s) => const SettingsScreen()),
      _pushed('/settings/notifications', (s) => const NotificationSettingsScreen()),

      // ---- Employer ---------------------------------------------------------
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => EmployerShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/employer/dashboard', builder: (c, s) => const DashboardScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/employer/insights', builder: (c, s) => const InsightsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/employer/jobs', builder: (c, s) => const MyJobsScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/employer/candidates', builder: (c, s) => CandidatesScreen(jobId: s.uri.queryParameters['job'])),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: '/employer/company', builder: (c, s) => const CompanyProfileScreen())]),
        ],
      ),
      _pushed('/employer/jobs/new', (s) => const JobEditorScreen()),
      _pushed('/employer/jobs/:id/edit', (s) => JobEditorScreen(jobId: s.pathParameters['id'])),
      _pushed('/employer/candidates/:id', (s) => CandidateDetailScreen(applicationId: s.pathParameters['id']!)),

      // ---- Shared -----------------------------------------------------------
      _pushed('/about', (s) => const AboutScreen()),
      _pushed('/account/delete', (s) => const DeleteAccountScreen()),
      _pushed('/pages/:slug', (s) => SitePageScreen(slug: s.pathParameters['slug']!)),
      GoRoute(path: '/suspended', pageBuilder: (c, s) => _page(s, const SuspendedScreen())),

      // ---- Admin ------------------------------------------------------------
      GoRoute(path: '/admin', redirect: (c, s) => '/admin/overview'),
      ShellRoute(
        builder: (context, state, child) => AdminShell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/admin/overview', pageBuilder: (c, s) => _page(s, const AdminOverviewScreen())),
          GoRoute(path: '/admin/insights', pageBuilder: (c, s) => _page(s, const AdminInsightsScreen())),
          GoRoute(path: '/admin/jobs', pageBuilder: (c, s) => _page(s, const AdminJobsScreen())),
          GoRoute(path: '/admin/employers', pageBuilder: (c, s) => _page(s, const AdminEmployersScreen())),
          GoRoute(path: '/admin/users', pageBuilder: (c, s) => _page(s, const AdminUsersScreen())),
          GoRoute(path: '/admin/applications', pageBuilder: (c, s) => _page(s, const AdminApplicationsScreen())),
          GoRoute(path: '/admin/reports', pageBuilder: (c, s) => _page(s, const AdminReportsScreen())),
          GoRoute(path: '/admin/content', pageBuilder: (c, s) => _page(s, const AdminContentScreen())),
          GoRoute(path: '/admin/settings', pageBuilder: (c, s) => _page(s, const AdminSettingsScreen())),
          GoRoute(path: '/admin/team', pageBuilder: (c, s) => _page(s, const AdminTeamScreen())),
          GoRoute(path: '/admin/activity', pageBuilder: (c, s) => _page(s, const AdminActivityScreen())),
        ],
      ),
      _pushed('/settings/password', (s) => ChangePasswordScreen(fromReset: s.uri.queryParameters['reset'] == '1')),
    ],
  );
});
