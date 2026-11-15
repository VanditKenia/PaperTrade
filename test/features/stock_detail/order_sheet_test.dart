import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:papertrade/data/portfolio_repository.dart';
import 'package:papertrade/domain/models/portfolio_state.dart';
import 'package:papertrade/domain/models/stock.dart';
import 'package:papertrade/domain/models/trade.dart';
import 'package:papertrade/domain/portfolio_engine.dart';
import 'package:papertrade/features/stock_detail/widgets/order_sheet.dart';
import 'package:papertrade/features/watchlist/watchlist_provider.dart';
import 'package:papertrade/domain/quantity.dart';

import '../../fakes.dart';

const aapl = Stock(symbol: 'AAPL', name: 'Apple Inc');
const price = 18942; // $189.42

Future<FakePortfolioRepository> openSheet(
  WidgetTester tester,
  TradeSide side, {
  PortfolioState? portfolio,
}) async {
  final repo = FakePortfolioRepository(portfolio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        portfolioRepositoryProvider.overrideWithValue(repo),
        latestPriceProvider('AAPL').overrideWithValue(price),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showOrderSheet(context, stock: aapl, side: side),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return repo;
}

FilledButton confirmButton(WidgetTester tester) =>
    tester.widget<FilledButton>(find.byType(FilledButton));

void main() {
  testWidgets('qty that exceeds cash disables Confirm and says '
      '"Not enough cash"', (tester) async {
    await openSheet(tester, TradeSide.buy);
    expect(confirmButton(tester).onPressed, isNotNull); // 1 share is fine

    await tester.enterText(find.byType(TextField), '1000'); // $189,420
    await tester.pump();

    expect(find.text('Not enough cash'), findsOneWidget);
    expect(confirmButton(tester).onPressed, isNull);
  });

  testWidgets('Max fills the max affordable quantity', (tester) async {
    await openSheet(tester, TradeSide.buy);
    await tester.tap(find.text('Max'));
    await tester.pump();

    // $100,000.00 / $189.42 = 527.92735… → the largest 4-decimal quantity
    // whose rounded cost still fits: 527.9273 ($99,999.99).
    expect(find.widgetWithText(TextField, '527.9273'), findsOneWidget);
    expect(find.text(r'$99,999.99'), findsOneWidget);
    expect(find.text('Not enough cash'), findsNothing);
    expect(confirmButton(tester).onPressed, isNotNull);
  });

  testWidgets('input accepts up to 4 decimals and nothing else', (
    tester,
  ) async {
    await openSheet(tester, TradeSide.buy);
    for (final bad in ['-3', '3.5x', '1.23456', '1.2.3']) {
      await tester.enterText(find.byType(TextField), bad);
      await tester.pump();
      expect(find.widgetWithText(TextField, '1'), findsOneWidget, reason: bad);
    }

    await tester.enterText(find.byType(TextField), '0.0001');
    await tester.pump();
    expect(find.widgetWithText(TextField, '0.0001'), findsOneWidget);
    expect(find.text(r'$0.02'), findsOneWidget); // $0.018942 → 2¢
    expect(confirmButton(tester).onPressed, isNotNull);
  });

  testWidgets('0 and empty are below the minimum', (tester) async {
    await openSheet(tester, TradeSide.buy);
    for (final text in ['0', '', '0.0000']) {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump();
      expect(find.text('Minimum quantity is 0.0001'), findsOneWidget);
      expect(confirmButton(tester).onPressed, isNull);
    }
  });

  group('amount mode', () {
    Future<void> enterAmount(WidgetTester tester, String dollars) async {
      await tester.tap(find.text(r'Amount ($)'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), dollars);
      await tester.pump();
    }

    testWidgets('converts dollars to a quantity that never costs more', (
      tester,
    ) async {
      final repo = await openSheet(tester, TradeSide.buy);
      await enterAmount(tester, '500');

      // $500 / $189.42 = 2.63963… → 2.6396 shares, cost $499.99.
      expect(find.text('2.6396 shares'), findsOneWidget);
      expect(find.text(r'$499.99'), findsOneWidget);

      await tester.tap(find.text('Confirm Buy'));
      await tester.pumpAndSettle();
      expect(repo.saved.holdings['AAPL']!.quantity, 26396);
      expect(find.text(r'Bought 2.6396 AAPL @ $189.42'), findsOneWidget);
    });

    testWidgets('accepts at most 2 decimals', (tester) async {
      await openSheet(tester, TradeSide.buy);
      await enterAmount(tester, '12.345');
      expect(find.widgetWithText(TextField, '12.345'), findsNothing);
    });

    testWidgets('switching back to Quantity keeps the converted amount', (
      tester,
    ) async {
      await openSheet(tester, TradeSide.buy);
      await enterAmount(tester, '500');
      await tester.tap(find.text('Quantity').first);
      await tester.pump();
      expect(find.widgetWithText(TextField, '2.6396'), findsOneWidget);
    });

    testWidgets('Max switches to Quantity with the exact amount', (
      tester,
    ) async {
      await openSheet(tester, TradeSide.buy);
      await enterAmount(tester, '10');
      await tester.tap(find.text('Max'));
      await tester.pump();
      expect(find.widgetWithText(TextField, '527.9273'), findsOneWidget);
    });
  });

  testWidgets('shows live cost and cash-after preview', (tester) async {
    await openSheet(tester, TradeSide.buy);
    await tester.enterText(find.byType(TextField), '5');
    await tester.pump();
    expect(find.text(r'$947.10'), findsOneWidget); // 5 × $189.42
    expect(find.text(r'$99,052.90'), findsOneWidget);
  });

  testWidgets('confirming a buy saves, closes and shows a snackbar', (
    tester,
  ) async {
    final repo = await openSheet(tester, TradeSide.buy);
    await tester.enterText(find.byType(TextField), '5');
    await tester.pump();
    await tester.tap(find.text('Confirm Buy'));
    await tester.pumpAndSettle();

    expect(repo.saved.holdings['AAPL']!.quantity, 5 * unitsPerShare);
    expect(find.byType(OrderSheet), findsNothing);
    expect(find.text(r'Bought 5 AAPL @ $189.42'), findsOneWidget);
  });

  testWidgets('failed save shows the error, logs it, and keeps the sheet', (
    tester,
  ) async {
    final repo = await openSheet(tester, TradeSide.buy);
    repo.failSaves = true;
    final logs = <String>[];
    final original = debugPrint;
    debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
    addTearDown(() => debugPrint = original);

    await tester.tap(find.text('Confirm Buy'));
    await tester.pumpAndSettle();

    // Tests run in debug mode, so the real cause is shown.
    expect(find.text('Could not save: Bad state: disk full'), findsOneWidget);
    expect(find.byType(OrderSheet), findsOneWidget);
    expect(
      logs.single,
      startsWith('Saving trade failed: StorageError: Bad state: disk full'),
    );
    expect(repo.saves, 0);
  });

  group('sell', () {
    final owns3 = PortfolioEngine.buy(
      PortfolioState.initial(),
      symbol: 'AAPL',
      quantity: 3 * unitsPerShare,
      priceCents: 18500,
    );

    testWidgets('previews realized P&L and blocks selling more than owned', (
      tester,
    ) async {
      await openSheet(tester, TradeSide.sell, portfolio: owns3);
      await tester.enterText(find.byType(TextField), '2');
      await tester.pump();
      expect(find.text('Estimated realized P&L'), findsOneWidget);
      expect(find.text(r'+$8.84'), findsOneWidget); // (189.42 − 185) × 2

      await tester.enterText(find.byType(TextField), '4');
      await tester.pump();
      expect(find.text('You own only 3 shares'), findsOneWidget);
      expect(confirmButton(tester).onPressed, isNull);
    });

    testWidgets('Max fills the number of shares owned', (tester) async {
      await openSheet(tester, TradeSide.sell, portfolio: owns3);
      await tester.tap(find.text('Max'));
      await tester.pump();
      expect(find.widgetWithText(TextField, '3'), findsOneWidget);
    });

    testWidgets('fractional holding: Max and realized P&L are exact', (
      tester,
    ) async {
      final owns2_5 = PortfolioEngine.buy(
        PortfolioState.initial(),
        symbol: 'AAPL',
        quantity: 25000,
        priceCents: 18500, // basis $462.50
      );
      await openSheet(tester, TradeSide.sell, portfolio: owns2_5);
      await tester.tap(find.text('Max'));
      await tester.pump();
      expect(find.widgetWithText(TextField, '2.5'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '1.25');
      await tester.pump();
      // Proceeds $236.775 → $236.78, minus half the basis $231.25.
      expect(find.text(r'+$5.53'), findsOneWidget);
    });
  });

  group('limit & stop orders', () {
    Future<void> choose(WidgetTester tester, String type) async {
      await tester.tap(find.text(type));
      await tester.pump();
    }

    Finder priceField() => find.byKey(const ValueKey('trigger-price'));

    testWidgets('limit buy: pre-filled price, note, reserves cash, places', (
      tester,
    ) async {
      final repo = await openSheet(tester, TradeSide.buy);
      expect(find.text('Stop-loss'), findsNothing); // sells only
      await choose(tester, 'Limit');

      expect(find.widgetWithText(TextField, '189.42'), findsOneWidget);
      expect(
        find.textContaining('Orders only execute while the app is open.'),
        findsOneWidget,
      );
      await tester.enterText(priceField(), '180');
      await tester.enterText(find.byType(TextField).last, '5');
      await tester.pump();
      expect(find.text('Cash reserved'), findsOneWidget);
      expect(find.text(r'$900.00'), findsOneWidget); // 5 × $180 limit

      await tester.tap(find.text('Place Buy order'));
      await tester.pumpAndSettle();
      final o = repo.saved.orders.single;
      expect(o.type, OrderType.limit);
      expect(o.triggerPriceCents, 18000);
      expect(o.quantity, 5 * unitsPerShare);
      expect(repo.saved.trades, isEmpty);
      expect(find.text(r'Limit buy 5 AAPL @ $180.00 placed'), findsOneWidget);
    });

    testWidgets('empty price blocks the order', (tester) async {
      await openSheet(tester, TradeSide.buy);
      await choose(tester, 'Limit');
      await tester.enterText(priceField(), '');
      await tester.pump();
      expect(find.text('Enter a limit price'), findsOneWidget);
      expect(confirmButton(tester).onPressed, isNull);

      await tester.enterText(priceField(), '1.234'); // 3 decimals rejected
      await tester.pump();
      expect(find.text('Enter a limit price'), findsOneWidget);
    });

    testWidgets('Max uses cash not reserved by open orders', (tester) async {
      final reserved = PortfolioEngine.placeOrder(
        PortfolioState.initial(),
        symbol: 'MSFT',
        side: TradeSide.buy,
        type: OrderType.limit,
        quantity: 900 * unitsPerShare,
        triggerPriceCents: 10000,
      ); // $90,000 reserved → $10,000 available
      await openSheet(tester, TradeSide.buy, portfolio: reserved);
      expect(find.text(r'$10,000.00'), findsOneWidget); // cash available
      await tester.tap(find.text('Max'));
      await tester.pump();
      // $10,000 / $189.42 → 52.7927
      expect(find.widgetWithText(TextField, '52.7927'), findsOneWidget);
    });

    testWidgets('stop-loss sell: shares in open orders are not available', (
      tester,
    ) async {
      final owns3 = PortfolioEngine.buy(
        PortfolioState.initial(),
        symbol: 'AAPL',
        quantity: 3 * unitsPerShare,
        priceCents: 18500,
      );
      final oneReserved = PortfolioEngine.placeOrder(
        owns3,
        symbol: 'AAPL',
        side: TradeSide.sell,
        type: OrderType.limit,
        quantity: unitsPerShare,
        triggerPriceCents: 20000,
      );
      final repo = await openSheet(
        tester,
        TradeSide.sell,
        portfolio: oneReserved,
      );
      await choose(tester, 'Stop-loss');
      expect(find.text('Stop price'), findsOneWidget);
      await tester.enterText(priceField(), '170');
      await tester.enterText(find.byType(TextField).last, '3');
      await tester.pump();
      expect(
        find.text('Only 2 shares available (rest in open orders)'),
        findsOneWidget,
      );

      await tester.tap(find.text('Max'));
      await tester.pump();
      expect(find.widgetWithText(TextField, '2'), findsOneWidget);
      await tester.tap(find.text('Place Sell order'));
      await tester.pumpAndSettle();
      expect(repo.saved.orders.last.type, OrderType.stopLoss);
      expect(repo.saved.availableQuantity('AAPL'), 0);
    });
  });
}
