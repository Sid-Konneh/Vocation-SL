// Employer app end to end on a fake backend:
// sign in -> company setup -> post job (pending approval) ->
// candidates table -> change stage -> candidate detail -> dashboard numbers.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:vocation_sl/core/dev_settings.dart';
import 'package:vocation_sl/core/network/connectivity_service.dart';
import 'package:vocation_sl/core/storage/local_store.dart';
import 'package:vocation_sl/data/backend/demo_backend.dart';
import 'package:vocation_sl/app.dart';
import 'package:vocation_sl/employer/providers.dart';
import 'package:vocation_sl/models/models.dart';
import 'package:vocation_sl/providers/core_providers.dart';

import 'package:vocation_sl/employer/data/demo_employer_backend.dart';

Future<void> settle(WidgetTester tester, [int ms = 600]) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> waitFor(WidgetTester tester, Finder finder, {int seconds = 10}) async {
  // ignore: avoid_print
  print('STEP waitFor ${finder.describeMatch(Plurality.many)}');
  for (var i = 0; i < seconds * 4; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await settle(tester, 250);
  }
  expect(finder, findsWidgets, reason: 'Timed out waiting for $finder');
}

/// Scrolls the visible vertical list until [finder] is on screen.
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
  setUp(() async => dir = await Directory.systemTemp.createTemp('vocation_employer'));
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

  testWidgets('employer can set up a company, post a job and manage candidates', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fake = DemoEmployerBackend();
    late ProviderContainer container;
    await tester.runAsync(() async {
      final store = await LocalStore.open(path: dir.path);
      final connectivity = ConnectivityService();
      await connectivity.init();
      container = ProviderContainer(overrides: [
        localStoreProvider.overrideWithValue(store),
        connectivityServiceProvider.overrideWithValue(connectivity),
        backendProvider.overrideWithValue(DemoBackend(store: store, connectivity: connectivity, devSettings: () => DevSettings.load(store))),
        employerBackendProvider.overrideWithValue(fake),
      ]);
    });
    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const VocationApp()));

    // Sign in (demo auth) -> company setup gate.
    await waitFor(tester, find.text('Hire talent'));
    await tester.tap(find.text('Hire talent'));
    await tester.pump();
    await waitFor(tester, find.text('Employer sign in'));
    await tester.tap(find.text('Continue with demo account'));
    await waitFor(tester, find.text('Set up your company'));

    // Submitting empty shows validation, then fill in the form.
    await reveal(tester, find.text('Create company profile'));
    await tester.tap(find.text('Create company profile'));
    await tester.pump();
    expect(find.text('Enter your company name'), findsOneWidget);
    await enter(tester, 'Company name *', 'Kroo Town Traders');
    await enter(tester, 'About the company *', 'We import and distribute building materials to hardware stores across the Western Area.');
    await enter(tester, 'Contact email *', 'accounts@kroo.example');
    await enter(tester, 'Phone *', '+232 76 555 444');
    await enter(tester, 'Business address *', '12 Wallace Johnson Street, Freetown');
    await reveal(tester, find.text('Create company profile'));
    await tester.tap(find.text('Create company profile'));
    await waitFor(tester, find.text('Here\'s how your hiring is going.'));
    expect(find.textContaining('Kroo Town Traders'), findsWidgets);
    expect(find.text('Your company is awaiting approval'), findsOneWidget);

    // Sidebar has every section.
    for (final s in ['Dashboard', 'Insights', 'My jobs', 'Candidates', 'Company profile', 'Switch to job seeker', 'Sign out']) {
      expect(find.text(s), findsWidgets, reason: s);
    }

    // Post a job.
    await tester.tap(find.text('Post a job').first);
    await waitFor(tester, find.text('Basics'));
    await enter(tester, 'Job title *', 'Store Accountant');
    await enter(tester, 'From', '4000');
    await enter(tester, 'To', '6000');
    await enter(tester, 'About the job (one-line summary) *', 'Keep the books for our Freetown warehouse.');
    await enter(tester, 'Full description *', 'You will manage day-to-day bookkeeping, reconcile mobile-money and bank accounts, and prepare monthly reports for management.');
    await enter(tester, 'Responsibilities *', 'Post transactions\nReconcile accounts');
    await enter(tester, 'Eligibility & requirements *', 'HND in Accounting');
    await enter(tester, 'Skills *', 'Excel\nQuickBooks');
    expect(find.textContaining('GST'), findsNothing, reason: 'billing removed');
    await tester.tap(find.text('Post job'));
    await waitFor(tester, find.text('Submit this job?'));
    await tester.tap(find.widgetWithText(FilledButton, 'Submit job'));
    await waitFor(tester, find.text('My jobs'));

    expect(fake.jobs.single.status, JobStatus.pending, reason: 'unapproved company');

    // Jobs table shows it as awaiting approval.
    await tester.tap(find.text('My jobs').first);
    await waitFor(tester, find.text('Store Accountant'));
    expect(find.text('Awaiting approval'), findsWidgets);
    expect(find.text('Invoices'), findsNothing);

    // A candidate applies; the ATS table lists them.
    fake.addApplicant(fake.jobs.single.id, 'Fatmata Kamara');
    await tester.tap(find.text('Candidates').first);
    unawaited(container.read(candidatesProvider.notifier).refresh());
    await waitFor(tester, find.text('Fatmata Kamara'));

    // Open the candidate: opening marks them viewed.
    await tester.tap(find.text('Fatmata Kamara'));
    await waitFor(tester, find.text('Schedule interview'));
    await settle(tester, 400);
    expect(fake.apps.single.status, ApplicationStatus.viewed);

    // Shortlist from the detail page.
    await tester.tap(find.widgetWithText(OutlinedButton, 'Shortlisted'));
    await settle(tester, 400);
    expect(fake.apps.single.status, ApplicationStatus.shortlisted);

    // Send a message: it appears in the conversation and on the application.
    final box = find.widgetWithText(TextField, 'Message to Fatmata');
    await tester.ensureVisible(box);
    await tester.enterText(box, 'Thanks for applying. We will be in touch this week.');
    await tester.ensureVisible(find.text('Send message'));
    await tester.tap(find.text('Send message'));
    await settle(tester, 400);
    expect(fake.apps.single.employerMessage, startsWith('Thanks for applying'));
    expect(find.textContaining('We will be in touch'), findsWidgets);

    // Dashboard reflects the pipeline.
    await tester.pageBack();
    await settle(tester, 300);
    await tester.tap(find.text('Dashboard').first);
    await waitFor(tester, find.text('Recent applicants'));
    expect(find.text('Fatmata Kamara'), findsWidgets);

    // Insights renders charts and the performance table.
    await tester.tap(find.text('Insights').first);
    await waitFor(tester, find.text('Applications per day'));
    expect(find.text('Hiring funnel'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    container.dispose();
  }, timeout: const Timeout(Duration(minutes: 8)));
}
