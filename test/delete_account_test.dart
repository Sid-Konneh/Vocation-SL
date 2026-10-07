// Delete account: typed confirmation, account removed, back at login, and
// the deleted credentials no longer work.
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

Future<void> reveal(WidgetTester tester, Finder finder) async {
  final vertical = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
  for (var i = 0; i < 30 && finder.hitTestable().evaluate().isEmpty; i++) {
    await tester.drag(vertical.first, const Offset(0, -300), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  late Directory dir;
  setUp(() async => dir = await Directory.systemTemp.createTemp('vocation_delete'));
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

  testWidgets('user can permanently delete their account', (tester) async {
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

    await waitFor(tester, find.text('Continue with demo account'));
    await tester.tap(find.text('Continue with demo account'));
    await waitFor(tester, find.text('Find your next role'));

    // Profile -> Settings -> Delete account
    await tester.tap(find.text('Profile').last);
    await settle(tester, 400);
    await tester.tap(find.byTooltip('Settings'));
    await waitFor(tester, find.text('Offline & sync'));
    await reveal(tester, find.text('Delete account'));
    await tester.tap(find.text('Delete account'));
    await waitFor(tester, find.text('Type DELETE to confirm'));

    // The button stays disabled until DELETE is typed.
    final button = find.widgetWithText(FilledButton, 'Delete my account permanently');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'delete');
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(button);
    await waitFor(tester, find.text('Welcome back'));

    // The old credentials no longer work.
    await tester.tap(find.text('Continue with demo account'));
    await waitFor(tester, find.textContaining('don\'t match'));

    await tester.pumpWidget(const SizedBox());
    container.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
