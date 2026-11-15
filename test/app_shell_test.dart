import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertrade/app.dart';
import 'package:papertrade/app_shell.dart';
import 'package:papertrade/features/watchlist/watchlist_provider.dart';
import 'package:papertrade/data/portfolio_repository.dart';
import 'package:papertrade/data/value_history_repository.dart';
import 'package:papertrade/data/alert_repository.dart';
import 'package:papertrade/data/notification_service.dart';
import 'package:papertrade/data/price_stream_service.dart';
import 'package:papertrade/domain/models/price_alert.dart';

import 'fakes.dart';

// Empty watchlist: the shell test shouldn't touch Hive or the network.
Widget shell({
  Stream<Map<String, int>> live = const Stream.empty(),
  List<PriceAlert> alerts = const [],
}) => ProviderScope(
  overrides: [
    watchlistProvider.overrideWithBuild((_, _) => []),
    showIntroProvider.overrideWithBuild((_, _) => false),
    // The order matcher and alert monitor listen to prices; keep the real
    // socket out.
    livePricesProvider.overrideWith((_) => live),
    marketOpenProvider.overrideWithValue(const AsyncData(true)),
    portfolioRepositoryProvider.overrideWithValue(FakePortfolioRepository()),
    valueHistoryRepositoryProvider.overrideWithValue(
      FakeValueHistoryRepository(),
    ),
    alertRepositoryProvider.overrideWithValue(FakeAlertRepository(alerts)),
    notificationServiceProvider.overrideWithValue(FakeNotificationService()),
    // Never started, so no socket; tests have no PROXY_BASE_URL anyway.
    priceStreamServiceProvider.overrideWithValue(
      PriceStreamService(
        testProxy,
        connect: (_) => throw StateError('no socket'),
      ),
    ),
  ],
  child: const MaterialApp(home: AppShell()),
);

void main() {
  testWidgets('tapping a tab switches the visible screen', (tester) async {
    await tester.pumpWidget(shell());

    int shownIndex() =>
        tester.widget<IndexedStack>(find.byType(IndexedStack)).index!;

    expect(shownIndex(), 0);
    await tester.tap(find.byIcon(Icons.pie_chart_outline));
    await tester.pump();
    expect(shownIndex(), 1);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    expect(shownIndex(), 3);
  });

  testWidgets('a fired price alert shows a snackbar', (tester) async {
    final live = StreamController<Map<String, int>>();
    addTearDown(live.close);
    await tester.pumpWidget(
      shell(
        live: live.stream,
        alerts: [
          PriceAlert(
            id: 'a',
            symbol: 'AAPL',
            direction: AlertDirection.above,
            targetCents: 20000,
            createdAt: DateTime(2026, 11, 15),
          ),
        ],
      ),
    );
    live.add({'AAPL': 19900});
    await tester.pump();
    live.add({'AAPL': 20050});
    await tester.pump();
    await tester.pump(); // snackbar entrance

    expect(find.text(r'AAPL rose above $200.00 · now $200.50'), findsOneWidget);
  });

  // Tests run without --dart-define, so PROXY_BASE_URL is empty.
  testWidgets('missing proxy URL shows the setup error screen', (tester) async {
    await tester.pumpWidget(const PaperTradeApp());

    expect(find.text('Proxy URL missing'), findsOneWidget);
    expect(find.byType(AppShell), findsNothing);
  });
}
