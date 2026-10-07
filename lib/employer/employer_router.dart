import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/about/about_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/profile/change_password_screen.dart';
import '../features/splash/splash_screen.dart';
import '../providers/session_providers.dart';
import 'employer_shell.dart';
import 'features/candidates/candidate_detail_screen.dart';
import 'features/candidates/candidates_screen.dart';
import 'features/company/company_screens.dart';
import 'features/dashboard/dashboard_screens.dart';
import 'features/jobs/job_editor_screen.dart';
import 'features/jobs/my_jobs_screen.dart';

final employerNavigatorKey = GlobalKey<NavigatorState>();

CustomTransitionPage<void> _page(GoRouterState state, Widget child) => CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 250),
      transitionsBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic), child: child),
    );

final employerRouterProvider = Provider<GoRouter>((ref) {
  final auth = ValueNotifier<String?>(ref.read(sessionProvider));
  ref.listen(sessionProvider, (_, next) => auth.value = next);
  ref.onDispose(auth.dispose);

  return GoRouter(
    navigatorKey: employerNavigatorKey,
    initialLocation: '/',
    refreshListenable: auth,
    redirect: (context, state) {
      final signedIn = auth.value != null;
      final loc = state.matchedLocation;
      if (loc == '/') return null;
      if (!signedIn && loc != '/login') return '/login';
      if (signedIn && loc == '/login') return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(
        path: '/',
        pageBuilder: (c, s) => _page(s, const SplashScreen(signedInPath: '/dashboard', tagline: 'Hire great people across Sierra Leone')),
      ),
      GoRoute(path: '/login', pageBuilder: (c, s) => _page(s, const LoginScreen(forEmployers: true))),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => EmployerShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/dashboard', builder: (c, s) => const DashboardScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/insights', builder: (c, s) => const InsightsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/jobs', builder: (c, s) => const MyJobsScreen())]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/candidates', builder: (c, s) => CandidatesScreen(jobId: s.uri.queryParameters['job'])),
          ]),
          StatefulShellBranch(routes: [GoRoute(path: '/company', builder: (c, s) => const CompanyProfileScreen())]),
        ],
      ),
      GoRoute(path: '/jobs/new', parentNavigatorKey: employerNavigatorKey, pageBuilder: (c, s) => _page(s, const JobEditorScreen())),
      GoRoute(
        path: '/jobs/:id/edit',
        parentNavigatorKey: employerNavigatorKey,
        pageBuilder: (c, s) => _page(s, JobEditorScreen(jobId: s.pathParameters['id'])),
      ),
      GoRoute(
        path: '/candidates/:id',
        parentNavigatorKey: employerNavigatorKey,
        pageBuilder: (c, s) => _page(s, CandidateDetailScreen(applicationId: s.pathParameters['id']!)),
      ),
      GoRoute(path: '/about', parentNavigatorKey: employerNavigatorKey, pageBuilder: (c, s) => _page(s, const AboutScreen())),
      GoRoute(
        path: '/settings/password',
        parentNavigatorKey: employerNavigatorKey,
        pageBuilder: (c, s) => _page(s, ChangePasswordScreen(fromReset: s.uri.queryParameters['reset'] == '1')),
      ),
    ],
  );
});
