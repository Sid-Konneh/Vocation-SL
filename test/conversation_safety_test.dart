// Report and block in an employer ⇄ candidate conversation (App Store
// guideline 1.2): the menu reports the other side, and blocking turns
// messages off until the blocker unblocks.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocation_sl/core/theme/app_theme.dart';
import 'package:vocation_sl/data/backend/message_backend.dart';
import 'package:vocation_sl/models/models.dart';
import 'package:vocation_sl/providers/message_providers.dart';
import 'package:vocation_sl/widgets/message_thread.dart';

void main() {
  late DemoMessageBackend backend;

  Future<void> pumpThread(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        messageBackendProvider.overrideWithValue(backend),
        messageThreadProvider.overrideWith((ref, id) async => <AppMessage>[]),
        conversationBlockProvider.overrideWith((ref, id) => backend.blockStatus(id)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SingleChildScrollView(child: MessageThread(applicationId: 'app-1', asEmployer: true, otherName: 'Aminata Sesay')),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  setUp(() => backend = DemoMessageBackend());

  testWidgets('blocking turns messages off, and unblocking turns them back on', (tester) async {
    await pumpThread(tester);
    expect(find.text('Send message'), findsOneWidget);

    await tester.tap(find.byTooltip('Report or block'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Block Aminata Sesay'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Block'));
    await tester.pumpAndSettle();

    expect(find.text('You blocked Aminata Sesay. Messages are off.'), findsOneWidget);
    expect(find.text('Send message'), findsNothing);

    await tester.tap(find.byTooltip('Report or block'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unblock Aminata Sesay'));
    await tester.pumpAndSettle();
    expect(find.text('Send message'), findsOneWidget);
  });

  testWidgets('reporting sends the chosen reason', (tester) async {
    await pumpThread(tester);
    await tester.tap(find.byTooltip('Report or block'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Report Aminata Sesay'));
    await tester.pumpAndSettle();

    final send = find.widgetWithText(FilledButton, 'Send report');
    expect(tester.widget<FilledButton>(send).onPressed, isNull); // a reason is required
    await tester.tap(find.text('Harassment or abusive language'));
    await tester.pumpAndSettle();
    await tester.tap(send);
    await tester.pumpAndSettle();

    expect(backend.reports, ['app-1: Harassment or abusive language']);
  });
}
