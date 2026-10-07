// End-to-end flow on the demo backend:
// splash -> demo login -> home -> search -> job details -> save -> apply
// (personal info, CV, cover letter, note, review) -> submit -> success ->
// application tracking -> offline mode.
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

/// Lets real timers (demo latency, Hive IO) run, then renders frames.
Future<void> settle(WidgetTester tester, [int ms = 700]) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> waitFor(WidgetTester tester, Finder finder, {int seconds = 10}) async {
  // ignore: avoid_print
  print('waitFor $finder');
  for (var i = 0; i < seconds * 4; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await settle(tester, 250);
  }
  expect(finder, findsWidgets, reason: 'Timed out waiting for $finder');
}

/// Drags the main vertical list until [finder] is built and on screen.
/// (Avoids scrollUntilVisible/ensureVisible, which wait for animations to
/// settle and never return while shimmer or progress animations run.)
Future<void> reveal(WidgetTester tester, Finder finder) async {
  final vertical = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down);
  final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
  for (var i = 0; i < 40; i++) {
    double dy = -250;
    if (finder.evaluate().isNotEmpty) {
      final r = tester.getRect(finder.first);
      if (r.top >= 70 && r.bottom <= screen.height - 90) return;
      if (r.center.dy < screen.height / 2) dy = 250;
    }
    if (vertical.evaluate().isEmpty) break;
    await tester.drag(vertical.first, Offset(0, dy), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
  }
  expect(finder, findsWidgets, reason: 'Could not scroll to $finder');
}

Future<void> tapText(WidgetTester tester, String text) async {
  await reveal(tester, find.text(text));
  await tester.tap(find.text(text).first);
  await settle(tester, 400);
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vocation_test');
  });

  tearDown(() async {
    // Writes queued inside the fake-async test zone never complete, so don't
    // let closing the boxes block teardown.
    try {
      await Hive.close().timeout(const Duration(seconds: 5));
    } on TimeoutException {
      // Ignored: see above.
    }
    try {
      await dir.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('demo user can find, save, apply for and track a job, including offline', (tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
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

    // Splash â†’ login
    await waitFor(tester, find.text('Continue with demo account'));

    // Demo login â†’ home
    await tapText(tester, 'Continue with demo account');
    await waitFor(tester, find.text('Find your next role'));
    await waitFor(tester, find.text('Latest jobs'));

    // Search with a keyword
    await tester.tap(find.text('Search jobs').first);
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'flutter');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await waitFor(tester, find.text('Flutter Mobile Developer'));

    // Apply a quick filter, then open the job
    await tapText(tester, 'Freetown');
    await waitFor(tester, find.text('Flutter Mobile Developer'));
    await tapText(tester, 'Flutter Mobile Developer');
    await waitFor(tester, find.text('Apply now'));
    await waitFor(tester, find.text('About the job'));
    await reveal(tester, find.text('Responsibilities'));
    await reveal(tester, find.text('Eligibility & requirements'));
    await reveal(tester, find.text('About the company'));

    // Toggle save off and on again
    final saveButton = find.byTooltip('Remove from saved').first;
    await tester.tap(saveButton);
    await settle(tester);
    await waitFor(tester, find.byTooltip('Save job'));
    await tester.tap(find.byTooltip('Save job').first);
    await settle(tester);
    await waitFor(tester, find.byTooltip('Remove from saved'));
    // Wait for the save request to finish, then dismiss its snack bar.
    await waitFor(tester, find.text('Saved Flutter Mobile Developer'));
    scaffoldMessengerKey.currentState?.clearSnackBars();
    await tester.pump(const Duration(seconds: 1));
    await settle(tester, 300);

    // Apply
    await tapText(tester, 'Apply now');
    await waitFor(tester, find.text('Confirm your details'));
    await tapText(tester, 'Next'); // personal info (prefilled)
    await waitFor(tester, find.text('Your CV'));
    expect(find.text('Aminata_Sesay_CV.pdf'), findsOneWidget);
    await tapText(tester, 'Next'); // CV from profile
    await waitFor(tester, find.text('Start from a template'));
    await tapText(tester, 'Start from a template');
    await tapText(tester, 'Next'); // cover letter
    await waitFor(tester, find.text('Message to the employer'));
    await tester.enterText(find.byType(TextField).first, 'I can start immediately.');
    await tapText(tester, 'Continue');
    await waitFor(tester, find.text('Review your application'));
    await reveal(tester, find.text('I can start immediately.'));

    // Submitting without confirming shows an error
    await tapText(tester, 'Submit application');
    await reveal(tester, find.text('Confirm that your information is accurate.'));
    await reveal(tester, find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox).first);
    await settle(tester, 200);
    await tapText(tester, 'Submit application');
    await waitFor(tester, find.text('Application sent!'));

    // Track it
    await tapText(tester, 'Track application');
    await waitFor(tester, find.text('Progress'));
    await waitFor(tester, find.text('Applied'));
    // ignore: avoid_print
    print('STEP tracking page shown');

    // Offline: banner appears while cached data stays on screen.
    // (Toggled on the service directly; persisting the switch is covered by the app.)
    final connectivity = container.read(connectivityServiceProvider);
    connectivity.simulateOffline = true;
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('Offline'), findsWidgets);
    expect(find.text('Progress'), findsOneWidget);
    // ignore: avoid_print
    print('STEP offline banner shown');
    connectivity.simulateOffline = false;
    await tester.pump(const Duration(milliseconds: 500));

    // The submission created an alert, visible in the Alerts tab
    await tester.pageBack();
    await settle(tester, 400);
    await tapText(tester, 'Alerts');
    await waitFor(tester, find.text('Application submitted'));
    // ignore: avoid_print
    print('STEP submitted alert shown');

    await tester.pumpWidget(const SizedBox());
    container.dispose();
  }, timeout: const Timeout(Duration(minutes: 10)));
}
