import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:papertrade/data/portfolio_repository.dart';
import 'package:papertrade/data/value_history_repository.dart';
import 'package:papertrade/domain/models/portfolio_state.dart';
import 'package:papertrade/domain/portfolio_engine.dart';
import 'package:papertrade/domain/quantity.dart';
import 'package:papertrade/domain/value_history.dart';
import 'package:papertrade/features/portfolio/portfolio_screen.dart';
import 'package:papertrade/features/stats/stats_screen.dart';
import 'package:papertrade/features/stock_detail/widgets/price_chart.dart';
import 'package:papertrade/features/watchlist/watchlist_provider.dart';

import '../../fakes.dart';

const sh = unitsPerShare;

Widget app(
  PortfolioState portfolio, {
  List<ValueSnapshot> history = const [],
  Widget home = const StatsScreen(),
}) => ProviderScope(
  overrides: [
    portfolioRepositoryProvider.overrideWithValue(
      FakePortfolioRepository(portfolio),
    ),
    valueHistoryRepositoryProvider.overrideWithValue(
      FakeValueHistoryRepository(history),
    ),
    watchlistProvider.overrideWithBuild((_, _) => const []),
    latestPriceProvider('AAPL').overrideWithValue(10000),
    latestPriceProvider('MSFT').overrideWithValue(10000),
  ],
  child: MaterialApp(home: home),
);

/// Tall enough that the lazy ListView builds every row.
void tallScreen(WidgetTester tester) {
  tester.view.physicalSize = const Size(2400, 4800);
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('no trades: hint, zero/dash values, chart empty state', (
    tester,
  ) async {
    tallScreen(tester);
    await tester.pumpWidget(app(PortfolioState.initial()));

    expect(
      find.text('No trades yet — stats appear after your first trade.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Not enough data yet — the chart fills in as you trade and keep '
        'the app open.',
      ),
      findsOneWidget,
    );
    expect(find.byType(PriceChart), findsNothing);
    expect(find.text(r'$0.00'), findsOneWidget); // realized P&L
    expect(find.text('0'), findsOneWidget); // trades
    expect(find.text('—'), findsNWidgets(5)); // win rate … worst
  });

  testWidgets('buys only: hint about sells', (tester) async {
    final s = PortfolioEngine.buy(
      PortfolioState.initial(),
      symbol: 'AAPL',
      quantity: sh,
      priceCents: 10000,
    );
    await tester.pumpWidget(app(s));
    expect(
      find.text('Win rate and P&L stats appear after your first sell.'),
      findsOneWidget,
    );
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('shows every metric and the value chart', (tester) async {
    tallScreen(tester);
    var s = PortfolioEngine.buy(
      PortfolioState.initial(),
      symbol: 'AAPL',
      quantity: 10 * sh,
      priceCents: 10000,
    );
    s = PortfolioEngine.buy(
      s,
      symbol: 'MSFT',
      quantity: 10 * sh,
      priceCents: 10000,
    );
    s = PortfolioEngine.sell(
      s,
      symbol: 'AAPL',
      quantity: 5 * sh,
      priceCents: 12000,
    ); // +100
    s = PortfolioEngine.sell(
      s,
      symbol: 'MSFT',
      quantity: 5 * sh,
      priceCents: 9000,
    ); // −50
    s = PortfolioEngine.sell(
      s,
      symbol: 'AAPL',
      quantity: 5 * sh,
      priceCents: 13000,
    ); // +150
    final t = DateTime(2026, 11, 15, 10);
    await tester.pumpWidget(
      app(
        s,
        history: [
          ValueSnapshot(time: t, valueCents: 10000000),
          ValueSnapshot(
            time: t.add(const Duration(minutes: 5)),
            valueCents: 10020000,
          ),
        ],
      ),
    );

    expect(find.byType(PriceChart), findsOneWidget);
    expect(find.text(r'+$200.00'), findsOneWidget); // realized P&L
    expect(find.text('5'), findsOneWidget); // trades
    expect(find.text('66.7% (2/3)'), findsOneWidget);
    expect(find.text(r'+$125.00'), findsOneWidget); // average win
    expect(find.text(r'-$50.00'), findsOneWidget); // average loss
    expect(find.text(r'+$150.00 · AAPL'), findsOneWidget); // best
    expect(find.text(r'-$50.00 · MSFT'), findsOneWidget); // worst
  });

  testWidgets('Portfolio → Stats button opens the Stats screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(PortfolioState.initial(), home: const PortfolioScreen()),
    );
    await tester.tap(find.byTooltip('Stats'));
    await tester.pumpAndSettle();
    expect(find.byType(StatsScreen), findsOneWidget);
  });
}
