// Desktop layout: sidebar with icon + label rows, About page and sign out.
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
import 'package:vocation_sl/providers/core_providers.dart';

Future<void> settle(WidgetTester tester, [int ms = 700]) async {
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

  setUp(() async => dir = await Directory.systemTemp.createTemp('vocation_desktop'));

  tearDown(() async {
    try {
      await Hive.close().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // Writes queued in the fake-async zone never finish; don't block teardown.
    }
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('desktop sidebar shows icon and label rows, About and Sign out', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    late ProviderContainer container;
    await tester.runAsync(() async {
      final store = await LocalStore.open(path: dir.path);
      final connectivity = ConnectivityService();
      await connectivity.init();
      final backend = DemoBackend(store: store, connectivity: connectivity, devSettings: () => DevSettings.load(store));
      container = ProviderContainer(overrides: [
        localStoreProvider.overrideWithValue(store),
        connectivityServiceProvider.overrideWithValue(connectivity),
        backendProvider.overrideWithValue(backend),
      ]);
    });
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const VocationApp()));

    await waitFor(tester, find.text('Continue with demo account'));
    await tester.tap(find.text('Continue with demo account'));
    await waitFor(tester, find.text('Find your next role'));

    // Sidebar items: icon and label on one row, full "Applications" label.
    for (final label in ['Jobs', 'Saved', 'Applications', 'Alerts', 'Profile', 'About', 'Sign out']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.byType(NavigationBar), findsNothing);
    final iconRect = tester.getRect(find.byIcon(Icons.info_outline_rounded));
    final labelRect = tester.getRect(find.text('About'));
    expect(labelRect.left, greaterThan(iconRect.right), reason: 'label sits to the right of the icon');
    expect((labelRect.center.dy - iconRect.center.dy).abs(), lessThan(4), reason: 'icon and label share a row');

    // Sidebar navigation switches tabs.
    await tester.tap(find.text('Applications').first);
    await waitFor(tester, find.textContaining('Interviews ('));

    // About page with support email.
    await tester.tap(find.text('About'));
    await waitFor(tester, find.text('About Vocation SL'));
    final emailFinder = find.text('vocationxsl@gmail.com');
    for (var i = 0; i < 12 && emailFinder.evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView).last, const Offset(0, -400), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
    }
    expect(emailFinder, findsOneWidget);
    await tester.pageBack();
    await settle(tester, 400);

    // Sign out asks for confirmation, then returns to login.
    await tester.tap(find.text('Sign out'));
    await settle(tester, 300);
    expect(find.text('Sign out?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await waitFor(tester, find.text('Welcome back'));

    await tester.pumpWidget(const SizedBox());
    container.dispose();
  }, timeout: const Timeout(Duration(minutes: 6)));
}
