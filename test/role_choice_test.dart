// The login switch decides which side opens, even if the account last used
// the other side: Hire talent -> company setup; Find a job -> job seeker home.
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
  expect(finder, findsWidgets, reason: 'Timed out waiting for $finder');
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('vocation_role'));
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

  testWidgets('login switch chooses the side on every sign-in', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    late ProviderContainer container;
    await tester.runAsync(() async {
      final store = await LocalStore.open(path: dir.path);
      final connectivity = ConnectivityService();
      await connectivity.init();
      container = ProviderContainer(overrides: [
        localStoreProvider.overrideWithValue(store),
        connectivityServiceProvider.overrideWithValue(connectivity),
        backendProvider.overrideWithValue(DemoBackend(store: store, connectivity: connectivity, devSettings: () => DevSettings.load(store))),
        employerBackendProvider.overrideWithValue(DemoEmployerBackend()),
      ]);
    });
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const VocationApp()));

    // 1. Hire talent -> employer side (company setup for a new employer).
    await waitFor(tester, find.text('Hire talent'));
    await tester.tap(find.text('Hire talent'));
    await tester.pump();
    await tester.tap(find.text('Continue with demo account'));
    await waitFor(tester, find.text('Set up your company'));

    // 2. Sign out.
    await tester.tap(find.text('Sign out'));
    await settle(tester, 300);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await waitFor(tester, find.text('Find a job'));

    // 3. Find a job -> job seeker home, not company setup.
    await tester.tap(find.text('Find a job'));
    await tester.pump();
    await tester.tap(find.text('Continue with demo account'));
    await waitFor(tester, find.text('Find your next role'));
    expect(find.text('Set up your company'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    container.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
