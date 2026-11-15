import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:papertrade/data/alert_repository.dart';
import 'package:papertrade/data/notification_service.dart';
import 'package:papertrade/domain/models/price_alert.dart';
import 'package:papertrade/features/alerts/widgets/alert_sheet.dart';
import 'package:papertrade/features/alerts/widgets/alerts_list.dart';

import '../../fakes.dart';

PriceAlert alert(String id, String symbol, {bool triggered = false}) {
  final a = PriceAlert(
    id: id,
    symbol: symbol,
    direction: AlertDirection.above,
    targetCents: 20000,
    createdAt: DateTime(2026, 11, 15),
  );
  return triggered ? a.triggered(20010, DateTime(2026, 11, 15, 14, 30)) : a;
}

Widget app(
  Widget home, {
  FakeAlertRepository? repo,
  FakeNotificationService? notifications,
}) => ProviderScope(
  overrides: [
    alertRepositoryProvider.overrideWithValue(repo ?? FakeAlertRepository()),
    notificationServiceProvider.overrideWithValue(
      notifications ?? FakeNotificationService(),
    ),
  ],
  child: MaterialApp(home: Scaffold(body: home)),
);

void main() {
  group('alert sheet', () {
    Future<void> open(
      WidgetTester tester, {
      FakeAlertRepository? repo,
      FakeNotificationService? notifications,
    }) async {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showAlertSheet(context, symbol: 'AAPL', priceCents: 18942),
              child: const Text('open'),
            ),
          ),
          repo: repo,
          notifications: notifications,
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    FilledButton create(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byType(FilledButton));

    testWidgets('pre-filled with the current price, which is not ahead', (
      tester,
    ) async {
      await open(tester);
      expect(find.widgetWithText(TextField, '189.42'), findsOneWidget);
      expect(find.text('Must be above the current price'), findsOneWidget);
      expect(create(tester).onPressed, isNull);
      expect(
        find.text('Fires once. Alerts only work while the app is open.'),
        findsOneWidget,
      );
    });

    testWidgets('direction changes the rule', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), '200');
      await tester.pump();
      expect(create(tester).onPressed, isNotNull);

      await tester.tap(find.text('Falls below'));
      await tester.pump();
      expect(find.text('Must be below the current price'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.text('Enter a price'), findsOneWidget);
    });

    testWidgets('creating saves, asks for permission, confirms', (
      tester,
    ) async {
      final repo = FakeAlertRepository();
      final notifications = FakeNotificationService();
      await open(tester, repo: repo, notifications: notifications);
      await tester.tap(find.text('Falls below'));
      await tester.enterText(find.byType(TextField), '180');
      await tester.pump();
      await tester.tap(find.text('Create alert'));
      await tester.pumpAndSettle();

      final a = repo.saved.single;
      expect(a.symbol, 'AAPL');
      expect(a.direction, AlertDirection.below);
      expect(a.targetCents, 18000);
      expect(notifications.permissionRequests, 1);
      expect(find.byType(AlertSheet), findsNothing);
      expect(find.text('Alert created'), findsOneWidget);
    });

    testWidgets('a failed save keeps the sheet open with a message', (
      tester,
    ) async {
      final repo = FakeAlertRepository()..failSaves = true;
      await open(tester, repo: repo);
      await tester.enterText(find.byType(TextField), '200');
      await tester.pump();
      await tester.tap(find.text('Create alert'));
      await tester.pumpAndSettle();
      expect(find.text('Could not save the alert'), findsOneWidget);
      expect(find.byType(AlertSheet), findsOneWidget);
    });
  });

  group('alerts list', () {
    testWidgets('StockDetail: only that symbol, with status and delete', (
      tester,
    ) async {
      final repo = FakeAlertRepository([
        alert('a', 'AAPL'),
        alert('b', 'MSFT'),
        alert('c', 'AAPL', triggered: true),
      ]);
      await tester.pumpWidget(
        app(const AlertsList(symbol: 'AAPL'), repo: repo),
      );

      expect(
        find.text('Alerts only work while the app is open.'),
        findsOneWidget,
      );
      expect(find.text(r'Rises above $200.00'), findsNWidgets(2));
      expect(find.text('Waiting'), findsOneWidget);
      expect(find.textContaining(r'Triggered Nov 15'), findsOneWidget);
      expect(find.textContaining(r'at $200.10'), findsOneWidget);

      await tester.tap(find.byTooltip('Delete alert').first);
      await tester.pump();
      expect(repo.saved.map((a) => a.id), ['a', 'b']); // newest shown first
    });

    testWidgets('Settings: all alerts with their symbol', (tester) async {
      final repo = FakeAlertRepository([
        alert('a', 'AAPL'),
        alert('b', 'MSFT'),
      ]);
      await tester.pumpWidget(app(const AlertsList(), repo: repo));
      expect(find.text(r'AAPL · Rises above $200.00'), findsOneWidget);
      expect(find.text(r'MSFT · Rises above $200.00'), findsOneWidget);
    });

    testWidgets('empty state', (tester) async {
      await tester.pumpWidget(app(const AlertsList()));
      expect(find.text('No price alerts'), findsOneWidget);
    });
  });
}
