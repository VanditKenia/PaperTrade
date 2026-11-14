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

    // $100,000.00 / $189.42 = 527.9… → 527 whole shares.
    expect(find.widgetWithText(TextField, '527'), findsOneWidget);
    expect(find.text('Not enough cash'), findsNothing);
  });

  testWidgets('input accepts digits only', (tester) async {
    await openSheet(tester, TradeSide.buy);
    await tester.enterText(find.byType(TextField), '-3.5x');
    await tester.pump();
    expect(find.widgetWithText(TextField, '35'), findsOneWidget);
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

    expect(repo.saved.holdings['AAPL']!.quantity, 5);
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
      quantity: 3,
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
  });
}
