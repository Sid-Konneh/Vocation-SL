// The "How Vocation SL works" guide: swipe through, skip, and finish with
// the first action for each side.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:vocation_sl/core/theme/app_theme.dart';
import 'package:vocation_sl/features/onboarding/onboarding_screen.dart';
import 'package:vocation_sl/models/models.dart';

Widget _app(UserRole role, List<String> visited) {
  final router = GoRouter(initialLocation: '/welcome', routes: [
    GoRoute(path: '/welcome', builder: (c, s) => OnboardingScreen(role: role)),
    for (final p in ['/jobs', '/profile/edit', '/employer/dashboard', '/employer/jobs/new'])
      GoRoute(path: p, builder: (c, s) {
        visited.add(p);
        return Scaffold(body: Text('page $p'));
      }),
  ]);
  return MaterialApp.router(theme: AppTheme.light(), routerConfig: router);
}

void main() {
  testWidgets('job seekers step through the guide and go to their profile', (tester) async {
    final visited = <String>[];
    await tester.pumpWidget(_app(UserRole.seeker, visited));
    expect(find.text('Welcome to Vocation SL'), findsOneWidget);
    for (final title in ['Complete your profile', 'Search and save jobs', 'Apply and track', 'Stay safe']) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
    }
    expect(find.text('Next'), findsNothing);
    await tester.tap(find.text('Complete my profile'));
    await tester.pumpAndSettle();
    expect(visited, contains('/profile/edit'));
  });

  testWidgets('skipping goes straight to the jobs', (tester) async {
    final visited = <String>[];
    await tester.pumpWidget(_app(UserRole.seeker, visited));
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(find.text('page /jobs'), findsOneWidget);
  });

  testWidgets('employers finish by posting their first job', (tester) async {
    final visited = <String>[];
    await tester.pumpWidget(_app(UserRole.employer, visited));
    expect(find.textContaining('Your company is set up'), findsOneWidget);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }
    expect(find.text('Find talent'), findsOneWidget);
    await tester.tap(find.text('Post my first job'));
    await tester.pumpAndSettle();
    expect(visited, contains('/employer/jobs/new'));
  });
}
