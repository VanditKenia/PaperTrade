import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:papertrade/data/portfolio_repository.dart';
import 'package:papertrade/domain/models/portfolio_state.dart';
import 'package:papertrade/domain/models/trade.dart';
import 'package:papertrade/domain/portfolio_engine.dart';
import 'package:papertrade/features/history/history_provider.dart';
import 'package:papertrade/features/history/history_screen.dart';
import 'package:papertrade/domain/quantity.dart';

import '../../fakes.dart';

Trade trade(String id, DateTime at) => Trade(
  id: id,
  symbol: 'AAPL',
  side: TradeSide.buy,
  quantity: 1 * unitsPerShare,
  priceCents: 100,
  executedAt: at,
);

Widget app(PortfolioState portfolio) => ProviderScope(
  overrides: [
    portfolioRepositoryProvider.overrideWithValue(
      FakePortfolioRepository(portfolio),
    ),
  ],
  child: const MaterialApp(home: HistoryScreen()),
);

void main() {
  test('groupByDay: newest day first, newest trade first within a day', () {
    final days = groupByDay([
      trade('a', DateTime(2026, 11, 13, 10)),
      trade('b', DateTime(2026, 11, 14, 9)),
      trade('c', DateTime(2026, 11, 14, 15)),
    ]);
    expect(days.map((d) => d.day), [
      DateTime(2026, 11, 14),
      DateTime(2026, 11, 13),
    ]);
    expect(days.first.trades.map((t) => t.id), ['c', 'b']);
    expect(days.last.trades.map((t) => t.id), ['a']);
  });

  testWidgets('no trades shows the empty state', (tester) async {
    await tester.pumpWidget(app(PortfolioState.initial()));
    expect(find.text('No trades yet'), findsOneWidget);
  });

  testWidgets('lists buys and sells with realized P&L on sells', (
    tester,
  ) async {
    var s = PortfolioEngine.buy(
      PortfolioState.initial(),
      symbol: 'AAPL',
      quantity: 5 * unitsPerShare,
      priceCents: 18500,
    );
    s = PortfolioEngine.sell(
      s,
      symbol: 'AAPL',
      quantity: 2 * unitsPerShare,
      priceCents: 19000,
    );
    await tester.pumpWidget(app(s));

    expect(find.text('BUY'), findsOneWidget);
    expect(find.text('SELL'), findsOneWidget);
    expect(find.text(r'5 AAPL @ $185.00'), findsOneWidget);
    expect(find.text(r'2 AAPL @ $190.00'), findsOneWidget);
    expect(find.text(r'+$10.00'), findsOneWidget); // (190 − 185) × 2
    expect(find.textContaining('· Market'), findsNWidgets(2));
  });

  testWidgets('marks how each trade was filled', (tester) async {
    var s = PortfolioEngine.buy(
      PortfolioState.initial(),
      symbol: 'AAPL',
      quantity: 5 * unitsPerShare,
      priceCents: 18500,
    );
    for (final type in [OrderType.limit, OrderType.stopLoss]) {
      s = PortfolioEngine.placeOrder(
        s,
        symbol: 'AAPL',
        side: TradeSide.sell,
        type: type,
        quantity: unitsPerShare,
        triggerPriceCents: 18000,
      );
      s = PortfolioEngine.fillOrder(
        s,
        orderId: s.orders.single.id,
        priceCents: 18000,
      );
    }
    await tester.pumpWidget(app(s));
    expect(find.textContaining('· Market'), findsOneWidget);
    expect(find.textContaining('· Limit'), findsOneWidget);
    expect(find.textContaining('· Stop-loss'), findsOneWidget);
  });
}
