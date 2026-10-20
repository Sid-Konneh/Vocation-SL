// A job seeker switches to employer, sets up their company once and lands on
// the dashboard. Switching away and back (also after the app restarts) opens
// the dashboard again, never the setup form, and never creates a second company.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vocation_sl/app.dart';
import 'package:vocation_sl/core/dev_settings.dart';
import 'package:vocation_sl/core/network/connectivity_service.dart';
import 'package:vocation_sl/core/storage/local_store.dart';
import 'package:vocation_sl/data/backend/demo_backend.dart';
import 'package:vocation_sl/employer/data/demo_employer_backend.dart';
import 'package:vocation_sl/employer/providers.dart';
import 'package:vocation_sl/providers/core_providers.dart';

Future<void> settle(WidgetTester tester, [int ms = 600]) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> waitFor(WidgetTester tester, Finder finder, {int seconds = 10}) async {
  for (var i = 0; i < seconds * 4; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await settle(tester, 250);
  }
  final onScreen = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).whereType<String>().take(40).join(' | ');
  expect(finder, findsWidgets, reason: 'Timed out waiting for $finder. On screen: $onScreen');
}

Future<void> reveal(WidgetTester tester, Finder finder) async {
  final vertical = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  for (var i = 0; i < 40; i++) {
    double dy = -300;
    if (finder.evaluate().isNotEmpty) {
      final r = tester.getRect(finder.first);
      if (r.top >= 60 && r.bottom <= screen.height - 20) return;
      if (r.center.dy < screen.height / 2) dy = 300;
    }
    await tester.drag(vertical.first, Offset(0, dy), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
  }
  expect(finder, findsWidgets, reason: 'Could not scroll to $finder');
}

Future<void> enter(WidgetTester tester, String label, String text) async {
  final f = find.widgetWithText(TextFormField, label);
  await reveal(tester, f);
  await tester.enterText(f.first, text);
  await tester.pump();
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('vocation_switch'));
  tearDown(() async {
    try {
      await Hive.close().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // Fake-async writes never finish; don't block teardown.
    }
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('job seeker switches to employer, sets up one company and reaches the dashboard', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final employer = DemoEmployerBackend();
    late ProviderContainer container;
    await tester.runAsync(() async {
      final store = await LocalStore.open(path: dir.path);
      final connectivity = ConnectivityService();
      await connectivity.init();
      container = ProviderContainer(overrides: [
        localStoreProvider.overrideWithValue(store),
        connectivityServiceProvider.overrideWithValue(connectivity),
        backendProvider.overrideWithValue(DemoBackend(store: store, connectivity: connectivity, devSettings: () => DevSettings.load(store))),
        employerBackendProvider.overrideWithValue(employer),
      ]);
    });
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const VocationApp()));

    // Sign in as a job seeker.
    await waitFor(tester, find.text('Find a job'));
    await tester.tap(find.text('Find a job'));
    await tester.pump();
    await tester.tap(find.text('Continue with demo account'));
    await waitFor(tester, find.text('Find your next role'));

    // Switch to employer: no company yet, so the setup form opens.
    await tester.tap(find.text('Switch to employer').first);
    await waitFor(tester, find.text('Set up your company'));

    await enter(tester, 'Company name *', 'Kroo Town Traders');
    await enter(tester, 'About the company *', 'We import and distribute building materials to hardware stores across the Western Area.');
    await enter(tester, 'Contact email *', 'accounts@kroo.example');
    await enter(tester, 'Phone *', '+232 76 555 444');
    await enter(tester, 'Business address *', '12 Wallace Johnson Street, Freetown');
    await reveal(tester, find.text('Create company profile'));
    await tester.tap(find.text('Create company profile'));

    // Straight to the dashboard.
    await waitFor(tester, find.text('Here\'s how your hiring is going.'));
    expect(find.text('Set up your company'), findsNothing);
    expect(employer.companiesCreated, 1);

    // Back to job seeker, then employer again: dashboard, not setup.
    await tester.tap(find.text('Switch to job seeker').first);
    await waitFor(tester, find.text('Find your next role'));
    await tester.tap(find.text('Switch to employer').first);
    await waitFor(tester, find.text('Here\'s how your hiring is going.'));
    expect(find.text('Set up your company'), findsNothing);

    // As after an app restart: the company is loaded again, still the dashboard.
    await tester.tap(find.text('Switch to job seeker').first);
    await waitFor(tester, find.text('Find your next role'));
    container.invalidate(companyProvider);
    await tester.tap(find.text('Switch to employer').first);
    await waitFor(tester, find.text('Here\'s how your hiring is going.'));
    expect(find.text('Set up your company'), findsNothing);

    // Only ever one company for this account.
    expect(employer.companiesCreated, 1);
    final again = await tester.runAsync(() => employer.registerCompany(employer.company!.copyWith(name: 'Second try')));
    expect(employer.companiesCreated, 1, reason: 'a second submit updates the same company');
    expect(again?.id, employer.company!.id);

    await tester.pumpWidget(const SizedBox());
    container.dispose();
  }, timeout: const Timeout(Duration(minutes: 6)));
}
