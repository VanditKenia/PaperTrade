import 'package:flutter_test/flutter_test.dart';
import 'package:papertrade/domain/models/holding.dart';
import 'package:papertrade/domain/models/portfolio_state.dart';
import 'package:papertrade/domain/models/trade.dart';
import 'package:papertrade/domain/models/wallet.dart';
import 'package:papertrade/domain/portfolio_engine.dart';
import 'package:papertrade/domain/trade_errors.dart';

void main() {
  final now = DateTime(2026, 11, 13, 10);
  late PortfolioState start;

  setUp(() => start = PortfolioState.initial());

  PortfolioState buy(
    PortfolioState s,
    int qty,
    int? price, [
    String symbol = 'AAPL',
  ]) => PortfolioEngine.buy(
    s,
    symbol: symbol,
    quantity: qty,
    priceCents: price,
    now: now,
  );

  PortfolioState sell(
    PortfolioState s,
    int qty,
    int? price, [
    String symbol = 'AAPL',
  ]) => PortfolioEngine.sell(
    s,
    symbol: symbol,
    quantity: qty,
    priceCents: price,
    now: now,
  );

  group('buy', () {
    test('deducts cost from cash and creates holding with avg = price', () {
      final s = buy(start, 10, 10000);
      expect(s.wallet.cashCents, 10000000 - 100000);
      expect(s.holdings['AAPL']!.quantity, 10);
      expect(s.holdings['AAPL']!.avgCostCents, 10000);
    });

    test(
      'buying more of an existing holding updates weighted average cost',
      () {
        final s = buy(buy(start, 10, 10000), 30, 12000);
        // (10 * 100 + 30 * 120) / 40 = 115
        expect(s.holdings['AAPL']!.quantity, 40);
        expect(s.holdings['AAPL']!.avgCostCents, 11500);
      },
    );

    test('weighted average rounds to the nearest cent', () {
      // (1 * 1000 + 2 * 1001) / 3 = 1000.67 → 1001
      final s = buy(buy(start, 1, 1000), 2, 1001);
      expect(s.holdings['AAPL']!.avgCostCents, 1001);
    });

    test('throws InsufficientFunds when cost > cash (state unchanged)', () {
      expect(() => buy(start, 10001, 1000), throwsA(isA<InsufficientFunds>()));
      expect(start.wallet.cashCents, startingCashCents);
      expect(start.holdings, isEmpty);
      expect(start.trades, isEmpty);
    });

    test('allows spending exactly all cash', () {
      expect(buy(start, 10000, 1000).wallet.cashCents, 0);
    });

    test('throws InvalidQuantity for qty 0 or negative', () {
      expect(() => buy(start, 0, 1000), throwsA(isA<InvalidQuantity>()));
      expect(() => buy(start, -1, 1000), throwsA(isA<InvalidQuantity>()));
    });

    test('throws PriceUnavailable when price is null/<=0', () {
      expect(() => buy(start, 1, null), throwsA(isA<PriceUnavailable>()));
      expect(() => buy(start, 1, 0), throwsA(isA<PriceUnavailable>()));
      expect(() => buy(start, 1, -5), throwsA(isA<PriceUnavailable>()));
    });

    test('appends a BUY trade with correct fields', () {
      final s = buy(start, 3, 2500);
      expect(s.trades, hasLength(1));
      final t = s.trades.single;
      expect(t.symbol, 'AAPL');
      expect(t.side, TradeSide.buy);
      expect(t.quantity, 3);
      expect(t.priceCents, 2500);
      expect(t.executedAt, now);
      expect(t.realizedPnlCents, isNull);
      expect(t.id, isNotEmpty);
    });

    test('state collections cannot be mutated from outside', () {
      final s = buy(start, 1, 1000);
      expect(() => s.holdings.remove('AAPL'), throwsUnsupportedError);
      expect(() => s.trades.clear(), throwsUnsupportedError);
    });
  });

  group('sell', () {
    late PortfolioState owned;
    setUp(() => owned = buy(start, 10, 10000));

    test('adds proceeds to cash and reduces quantity', () {
      final s = sell(owned, 4, 11000);
      expect(s.wallet.cashCents, owned.wallet.cashCents + 44000);
      expect(s.holdings['AAPL']!.quantity, 6);
    });

    test('computes realized P&L = (price - avg) * qty', () {
      expect(sell(owned, 4, 11000).trades.last.realizedPnlCents, 4000);
      expect(sell(owned, 4, 9000).trades.last.realizedPnlCents, -4000);
    });

    test('selling all shares removes the holding', () {
      final s = sell(owned, 10, 10000);
      expect(s.holdings.containsKey('AAPL'), isFalse);
    });

    test('avg cost is unchanged after a partial sell', () {
      expect(sell(owned, 3, 15000).holdings['AAPL']!.avgCostCents, 10000);
    });

    test('throws InsufficientShares when qty > owned', () {
      expect(() => sell(owned, 11, 10000), throwsA(isA<InsufficientShares>()));
      expect(owned.holdings['AAPL']!.quantity, 10);
    });

    test('throws InsufficientShares when no holding exists', () {
      expect(
        () => sell(owned, 1, 10000, 'TSLA'),
        throwsA(isA<InsufficientShares>()),
      );
    });

    test('throws InvalidQuantity and PriceUnavailable', () {
      expect(() => sell(owned, 0, 10000), throwsA(isA<InvalidQuantity>()));
      expect(() => sell(owned, 1, null), throwsA(isA<PriceUnavailable>()));
    });

    test('appends a SELL trade', () {
      final t = sell(owned, 2, 10500).trades.last;
      expect(t.side, TradeSide.sell);
      expect(t.quantity, 2);
      expect(t.priceCents, 10500);
      expect(t.id, isNot(owned.trades.first.id));
    });
  });

  group('summary', () {
    test('portfolio value = cash + Σ qty * livePrice', () {
      final s = buy(buy(start, 10, 10000), 5, 20000, 'MSFT');
      final sum = PortfolioEngine.summary(s, {'AAPL': 11000, 'MSFT': 19000});
      expect(sum.marketValueCents, 10 * 11000 + 5 * 19000);
      expect(
        sum.portfolioValueCents,
        s.wallet.cashCents + 10 * 11000 + 5 * 19000,
      );
    });

    test('unrealized P&L and % correct for gain and loss', () {
      const h = Holding(symbol: 'AAPL', quantity: 10, avgCostCents: 10000);
      expect(PortfolioEngine.unrealizedPnl(h, 11000), 10000);
      expect(PortfolioEngine.unrealizedPnlPercent(h, 11000), closeTo(10, 1e-9));
      expect(PortfolioEngine.unrealizedPnl(h, 9500), -5000);
      expect(PortfolioEngine.unrealizedPnlPercent(h, 9500), closeTo(-5, 1e-9));
      expect(PortfolioEngine.marketValue(h, 9500), 95000);
    });

    test(r'total return vs $100,000 start', () {
      final s = buy(start, 100, 10000);
      final sum = PortfolioEngine.summary(s, {'AAPL': 12000});
      expect(sum.totalReturnCents, 200000);
      expect(sum.totalReturnPercent, closeTo(2, 1e-9));
    });
  });

  group('reset', () {
    test('returns cash 10_000_000, no holdings, no trades', () {
      final s = PortfolioEngine.reset();
      expect(s.wallet.cashCents, 10000000);
      expect(s.holdings, isEmpty);
      expect(s.trades, isEmpty);
    });
  });

  test('worked example from TESTING.md', () {
    var s = start;
    expect(s.wallet.cashCents, 10000000);

    s = buy(s, 10, 10000);
    expect(s.wallet.cashCents, 9900000);
    expect(s.holdings['AAPL']!.quantity, 10);
    expect(s.holdings['AAPL']!.avgCostCents, 10000);

    s = buy(s, 10, 11000);
    expect(s.wallet.cashCents, 9790000);
    expect(s.holdings['AAPL']!.quantity, 20);
    expect(s.holdings['AAPL']!.avgCostCents, 10500);

    s = sell(s, 5, 12000);
    expect(s.wallet.cashCents, 9850000);
    expect(s.holdings['AAPL']!.quantity, 15);
    expect(s.holdings['AAPL']!.avgCostCents, 10500);
    expect(s.trades.last.realizedPnlCents, 7500);

    final sum = PortfolioEngine.summary(s, {'AAPL': 10000});
    expect(sum.unrealizedPnlCents, -7500);
    expect(sum.portfolioValueCents, 10000000);
  });
}
