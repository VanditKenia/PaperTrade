import 'package:flutter_test/flutter_test.dart';
import 'package:papertrade/domain/models/holding.dart';
import 'package:papertrade/domain/models/portfolio_state.dart';
import 'package:papertrade/domain/models/trade.dart';
import 'package:papertrade/domain/models/wallet.dart';
import 'package:papertrade/domain/portfolio_engine.dart';
import 'package:papertrade/domain/quantity.dart';
import 'package:papertrade/domain/trade_errors.dart';

const sh = unitsPerShare; // one whole share in quantity units

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
      final s = buy(start, 10 * sh, 10000);
      expect(s.wallet.cashCents, 10000000 - 100000);
      expect(s.holdings['AAPL']!.quantity, 10 * sh);
      expect(s.holdings['AAPL']!.avgCostCents, 10000);
    });

    test(
      'buying more of an existing holding updates weighted average cost',
      () {
        final s = buy(buy(start, 10 * sh, 10000), 30 * sh, 12000);
        // (10 * 100 + 30 * 120) / 40 = 115
        expect(s.holdings['AAPL']!.quantity, 40 * sh);
        expect(s.holdings['AAPL']!.avgCostCents, 11500);
      },
    );

    test('weighted average rounds to the nearest cent', () {
      // (1 * 1000 + 2 * 1001) / 3 = 1000.67 → 1001
      final s = buy(buy(start, 1 * sh, 1000), 2 * sh, 1001);
      expect(s.holdings['AAPL']!.avgCostCents, 1001);
    });

    test('throws InsufficientFunds when cost > cash (state unchanged)', () {
      expect(
        () => buy(start, 10001 * sh, 1000),
        throwsA(isA<InsufficientFunds>()),
      );
      expect(start.wallet.cashCents, defaultStartingCashCents);
      expect(start.holdings, isEmpty);
      expect(start.trades, isEmpty);
    });

    test('allows spending exactly all cash', () {
      expect(buy(start, 10000 * sh, 1000).wallet.cashCents, 0);
    });

    test('throws InvalidQuantity for qty 0 or negative', () {
      expect(() => buy(start, 0, 1000), throwsA(isA<InvalidQuantity>()));
      expect(() => buy(start, -1, 1000), throwsA(isA<InvalidQuantity>()));
    });

    test('throws PriceUnavailable when price is null/<=0', () {
      expect(() => buy(start, 1 * sh, null), throwsA(isA<PriceUnavailable>()));
      expect(() => buy(start, 1 * sh, 0), throwsA(isA<PriceUnavailable>()));
      expect(() => buy(start, 1 * sh, -5), throwsA(isA<PriceUnavailable>()));
    });

    test('appends a BUY trade with correct fields', () {
      final s = buy(start, 3 * sh, 2500);
      expect(s.trades, hasLength(1));
      final t = s.trades.single;
      expect(t.symbol, 'AAPL');
      expect(t.side, TradeSide.buy);
      expect(t.quantity, 3 * sh);
      expect(t.priceCents, 2500);
      expect(t.executedAt, now);
      expect(t.realizedPnlCents, isNull);
      expect(t.id, isNotEmpty);
    });

    test('state collections cannot be mutated from outside', () {
      final s = buy(start, 1 * sh, 1000);
      expect(() => s.holdings.remove('AAPL'), throwsUnsupportedError);
      expect(() => s.trades.clear(), throwsUnsupportedError);
    });
  });

  group('sell', () {
    late PortfolioState owned;
    setUp(() => owned = buy(start, 10 * sh, 10000));

    test('adds proceeds to cash and reduces quantity', () {
      final s = sell(owned, 4 * sh, 11000);
      expect(s.wallet.cashCents, owned.wallet.cashCents + 44000);
      expect(s.holdings['AAPL']!.quantity, 6 * sh);
    });

    test('computes realized P&L = (price - avg) * qty', () {
      expect(sell(owned, 4 * sh, 11000).trades.last.realizedPnlCents, 4000);
      expect(sell(owned, 4 * sh, 9000).trades.last.realizedPnlCents, -4000);
    });

    test('selling all shares removes the holding', () {
      final s = sell(owned, 10 * sh, 10000);
      expect(s.holdings.containsKey('AAPL'), isFalse);
    });

    test('avg cost is unchanged after a partial sell', () {
      expect(sell(owned, 3 * sh, 15000).holdings['AAPL']!.avgCostCents, 10000);
    });

    test('throws InsufficientShares when qty > owned', () {
      expect(
        () => sell(owned, 11 * sh, 10000),
        throwsA(isA<InsufficientShares>()),
      );
      expect(owned.holdings['AAPL']!.quantity, 10 * sh);
    });

    test('throws InsufficientShares when no holding exists', () {
      expect(
        () => sell(owned, 1 * sh, 10000, 'TSLA'),
        throwsA(isA<InsufficientShares>()),
      );
    });

    test('throws InvalidQuantity and PriceUnavailable', () {
      expect(() => sell(owned, 0, 10000), throwsA(isA<InvalidQuantity>()));
      expect(() => sell(owned, 1 * sh, null), throwsA(isA<PriceUnavailable>()));
    });

    test('appends a SELL trade', () {
      final t = sell(owned, 2 * sh, 10500).trades.last;
      expect(t.side, TradeSide.sell);
      expect(t.quantity, 2 * sh);
      expect(t.priceCents, 10500);
      expect(t.id, isNot(owned.trades.first.id));
    });
  });

  group('summary', () {
    test('portfolio value = cash + Σ qty * livePrice', () {
      final s = buy(buy(start, 10 * sh, 10000), 5 * sh, 20000, 'MSFT');
      final sum = PortfolioEngine.summary(s, {'AAPL': 11000, 'MSFT': 19000});
      expect(sum.marketValueCents, 10 * 11000 + 5 * 19000);
      expect(sum.investedCents, 10 * 10000 + 5 * 20000);
      expect(
        sum.portfolioValueCents,
        s.wallet.cashCents + 10 * 11000 + 5 * 19000,
      );
    });

    test('unrealized P&L and % correct for gain and loss', () {
      const h = Holding(
        symbol: 'AAPL',
        quantity: 10 * sh,
        costBasisCents: 100000,
      );
      expect(PortfolioEngine.unrealizedPnl(h, 11000), 10000);
      expect(PortfolioEngine.unrealizedPnlPercent(h, 11000), closeTo(10, 1e-9));
      expect(PortfolioEngine.unrealizedPnl(h, 9500), -5000);
      expect(PortfolioEngine.unrealizedPnlPercent(h, 9500), closeTo(-5, 1e-9));
      expect(PortfolioEngine.marketValue(h, 9500), 95000);
    });

    test(r'total return vs $100,000 start', () {
      final s = buy(start, 100 * sh, 10000);
      final sum = PortfolioEngine.summary(s, {'AAPL': 12000});
      expect(sum.totalReturnCents, 200000);
      expect(sum.totalReturnPercent, closeTo(2, 1e-9));
      expect(sum.startingCashCents, 10000000);
    });

    test(r'total return vs a custom $10,000 start', () {
      final s = PortfolioEngine.buy(
        PortfolioEngine.reset(1000000),
        symbol: 'AAPL',
        quantity: 10 * sh,
        priceCents: 10000,
      );
      final sum = PortfolioEngine.summary(s, {'AAPL': 12000});
      expect(sum.portfolioValueCents, 1020000); // $9,000 cash + $1,200
      expect(sum.totalReturnCents, 20000);
      expect(sum.totalReturnPercent, closeTo(2, 1e-9)); // vs $10,000
      expect(sum.startingCashCents, 1000000);
    });

    test('buy and sell keep the starting balance', () {
      var s = PortfolioEngine.reset(500000);
      s = PortfolioEngine.buy(s, symbol: 'A', quantity: sh, priceCents: 100);
      s = PortfolioEngine.sell(s, symbol: 'A', quantity: sh, priceCents: 100);
      expect(s.startingCashCents, 500000);
    });
  });

  group('reset', () {
    test('custom amount: cash = start, no holdings, no trades', () {
      final s = PortfolioEngine.reset(5000000);
      expect(s.wallet.cashCents, 5000000);
      expect(s.startingCashCents, 5000000);
      expect(s.holdings, isEmpty);
      expect(s.trades, isEmpty);
    });

    test(r'bounds: $100 and $10,000,000 are allowed', () {
      expect(PortfolioEngine.reset(10000).wallet.cashCents, 10000);
      expect(PortfolioEngine.reset(1000000000).wallet.cashCents, 1000000000);
    });

    test('below min, above max, cents or ≤ 0 → InvalidStartingBalance', () {
      for (final bad in [9900, 1000000100, 10050, 0, -10000]) {
        expect(
          () => PortfolioEngine.reset(bad),
          throwsA(isA<InvalidStartingBalance>()),
          reason: '$bad',
        );
      }
    });
  });

  group('fractional', () {
    test('buy 0.5 share: cost rounds half up, basis = cost', () {
      final s = buy(start, 5000, 18943); // 0.5 × $189.43 = $94.715
      expect(s.wallet.cashCents, 10000000 - 9472);
      expect(s.holdings['AAPL']!.quantity, 5000);
      expect(s.holdings['AAPL']!.costBasisCents, 9472);
      expect(s.holdings['AAPL']!.avgCostCents, 18944); // 9472 / 0.5
    });

    test('order worth less than half a cent → OrderTooSmall', () {
      // 0.0001 × $49.99 = $0.004999 → 0 cents.
      expect(() => buy(start, 1, 4999), throwsA(isA<OrderTooSmall>()));
      final owned = buy(start, sh, 4999);
      expect(() => sell(owned, 1, 4999), throwsA(isA<OrderTooSmall>()));
    });

    test('minimum quantity 0.0001 works when it is worth a cent', () {
      final s = buy(start, 1, 5000); // $0.005 → 1 cent
      expect(s.wallet.cashCents, 10000000 - 1);
      expect(s.holdings['AAPL']!.quantity, 1);
    });

    test('partial sells take a proportional basis; avg cost unchanged', () {
      var s = buy(start, 3 * sh, 10001); // basis 30003
      s = sell(s, sh, 10001);
      expect(s.holdings['AAPL']!.costBasisCents, 20002);
      expect(s.holdings['AAPL']!.avgCostCents, 10001);
      expect(s.trades.last.realizedPnlCents, 0);
    });

    test('selling everything realizes the exact total P&L', () {
      var s = buy(start, 3333, 10000); // 0.3333 × $100 = $33.33
      s = buy(s, 1, 33333); // 0.0001 × $333.33 = 3.3333¢ → 3¢
      s = sell(s, 1111, 12345); // three uneven partial sells…
      s = sell(s, 1111, 9999);
      s = sell(s, 1112, 15000); // …that empty the holding
      expect(s.holdings, isEmpty);
      // Exact: total P&L = everything received − everything paid.
      final realized = s.trades.fold(
        0,
        (sum, t) => sum + (t.realizedPnlCents ?? 0),
      );
      expect(realized, s.wallet.cashCents - 10000000);
    });

    test('cash + basis − realized always equals the starting cash', () {
      var s = start;
      final steps = [
        (true, 12345, 18942),
        (true, 7, 6001),
        (false, 4321, 19999),
        (true, 9999, 17777),
        (false, 777, 15001),
      ];
      for (final (isBuy, qty, price) in steps) {
        s = isBuy ? buy(s, qty, price) : sell(s, qty, price);
        final basis = s.holdings.values.fold(
          0,
          (sum, h) => sum + h.costBasisCents,
        );
        final realized = s.trades.fold(
          0,
          (sum, t) => sum + (t.realizedPnlCents ?? 0),
        );
        expect(s.wallet.cashCents + basis - realized, 10000000);
      }
    });

    test('realizedPnl matches what sell records', () {
      final s = buy(start, 12345, 18942);
      final h = s.holdings['AAPL']!;
      expect(
        PortfolioEngine.realizedPnl(h, 4321, 19999),
        sell(s, 4321, 19999).trades.last.realizedPnlCents,
      );
    });

    test('summary uses exact cost for market value and P&L', () {
      final s = buy(start, 15000, 10001); // 1.5 × $100.01 = $150.015 → 15002
      final sum = PortfolioEngine.summary(s, {'AAPL': 10001});
      expect(sum.investedCents, 15002);
      expect(sum.marketValueCents, 15002);
      expect(sum.unrealizedPnlCents, 0);
    });
  });

  group('orders', () {
    PortfolioState place(
      PortfolioState s,
      TradeSide side,
      OrderType type,
      int qty,
      int? price,
    ) => PortfolioEngine.placeOrder(
      s,
      symbol: 'AAPL',
      side: side,
      type: type,
      quantity: qty,
      triggerPriceCents: price,
      now: now,
    );

    PortfolioState fill(PortfolioState s, int price, [int i = 0]) =>
        PortfolioEngine.fillOrder(
          s,
          orderId: s.orders[i].id,
          priceCents: price,
          now: now,
        );

    late PortfolioState owns10;
    setUp(() => owns10 = buy(start, 10 * sh, 10000));

    test('limit buy reserves cash at the limit; cash itself is untouched', () {
      final s = place(start, TradeSide.buy, OrderType.limit, 10 * sh, 18000);
      expect(s.orders, hasLength(1));
      expect(s.wallet.cashCents, 10000000);
      expect(s.reservedCashCents, 180000);
      expect(s.availableCashCents, 10000000 - 180000);
      expect(s.trades, isEmpty);
    });

    test('sell orders reserve quantity', () {
      var s = place(owns10, TradeSide.sell, OrderType.limit, 4 * sh, 12000);
      s = place(s, TradeSide.sell, OrderType.stopLoss, 5 * sh, 9000);
      expect(s.availableQuantity('AAPL'), 1 * sh);
      expect(s.holdings['AAPL']!.quantity, 10 * sh);
    });

    test('reserved cash cannot be spent twice (partial availability)', () {
      // $100,000 cash, $90,000 reserved → $10,000 available.
      final s = place(start, TradeSide.buy, OrderType.limit, 900 * sh, 10000);
      expect(buy(s, 100 * sh, 10000).wallet.cashCents, 10000000 - 1000000);
      expect(() => buy(s, 101 * sh, 10000), throwsA(isA<InsufficientFunds>()));
      expect(
        () => place(s, TradeSide.buy, OrderType.limit, 101 * sh, 10000),
        throwsA(isA<InsufficientFunds>()),
      );
    });

    test('reserved shares cannot be sold twice (partial availability)', () {
      final s = place(owns10, TradeSide.sell, OrderType.stopLoss, 6 * sh, 9000);
      expect(sell(s, 4 * sh, 10000).holdings['AAPL']!.quantity, 6 * sh);
      expect(() => sell(s, 5 * sh, 10000), throwsA(isA<InsufficientShares>()));
      expect(
        () => place(s, TradeSide.sell, OrderType.limit, 5 * sh, 12000),
        throwsA(isA<InsufficientShares>()),
      );
    });

    test('cancel releases the reservation', () {
      var s = place(start, TradeSide.buy, OrderType.limit, 10 * sh, 18000);
      s = PortfolioEngine.cancelOrder(s, s.orders.single.id);
      expect(s.orders, isEmpty);
      expect(s.availableCashCents, 10000000);
      expect(
        () => PortfolioEngine.cancelOrder(s, 'gone'),
        throwsA(isA<OrderNotFound>()),
      );
    });

    test('limit buy fills at the tick price, below the limit', () {
      var s = place(start, TradeSide.buy, OrderType.limit, 10 * sh, 18000);
      s = fill(s, 17500);
      expect(s.orders, isEmpty);
      expect(s.reservedCashCents, 0);
      expect(s.wallet.cashCents, 10000000 - 175000); // not the $1,800 reserved
      expect(s.holdings['AAPL']!.costBasisCents, 175000);
      final t = s.trades.single;
      expect(t.orderType, OrderType.limit);
      expect(t.priceCents, 17500);
      expect(t.side, TradeSide.buy);
    });

    test('limit sell and stop-loss fill with realized P&L', () {
      var s = place(owns10, TradeSide.sell, OrderType.limit, 4 * sh, 12000);
      s = fill(s, 12100);
      expect(s.trades.last.orderType, OrderType.limit);
      expect(s.trades.last.realizedPnlCents, 8400); // (121 − 100) × 4

      s = place(s, TradeSide.sell, OrderType.stopLoss, 6 * sh, 9000);
      s = fill(s, 8900);
      expect(s.trades.last.orderType, OrderType.stopLoss);
      expect(s.trades.last.realizedPnlCents, -6600); // (89 − 100) × 6
      expect(s.holdings, isEmpty);
    });

    test('a fill can use its own reserved cash even with none left over', () {
      // Reserve every cent, then fill: the reservation pays for it.
      var s = place(start, TradeSide.buy, OrderType.limit, 1000 * sh, 10000);
      expect(s.availableCashCents, 0);
      s = fill(s, 10000);
      expect(s.wallet.cashCents, 0);
    });

    test('fill rejects a price that does not meet the condition', () {
      final s = place(start, TradeSide.buy, OrderType.limit, sh, 18000);
      expect(() => fill(s, 18001), throwsA(isA<OrderNotTriggered>()));
      expect(
        () => PortfolioEngine.fillOrder(s, orderId: 'x', priceCents: 1),
        throwsA(isA<OrderNotFound>()),
      );
    });

    test('validation: quantity, price, value, ownership, type', () {
      expect(
        () => place(start, TradeSide.buy, OrderType.limit, 0, 100),
        throwsA(isA<InvalidQuantity>()),
      );
      for (final bad in [null, 0, -1]) {
        expect(
          () => place(start, TradeSide.buy, OrderType.limit, sh, bad),
          throwsA(isA<InvalidOrderPrice>()),
        );
      }
      expect(
        () => place(start, TradeSide.buy, OrderType.limit, 1, 4999),
        throwsA(isA<OrderTooSmall>()),
      );
      expect(
        () => place(start, TradeSide.sell, OrderType.limit, sh, 100),
        throwsA(isA<InsufficientShares>()),
      );
      expect(
        () => place(start, TradeSide.buy, OrderType.stopLoss, sh, 100),
        throwsArgumentError,
      );
      expect(
        () => place(start, TradeSide.buy, OrderType.market, sh, 100),
        throwsArgumentError,
      );
    });

    test('input state is never changed', () {
      final s = place(owns10, TradeSide.sell, OrderType.limit, 4 * sh, 12000);
      fill(s, 12000);
      PortfolioEngine.cancelOrder(s, s.orders.single.id);
      expect(s.orders, hasLength(1));
      expect(s.holdings['AAPL']!.quantity, 10 * sh);
    });

    test('market trades keep open orders; reset clears them', () {
      var s = place(owns10, TradeSide.sell, OrderType.limit, 4 * sh, 12000);
      s = buy(s, sh, 10000);
      expect(s.orders, hasLength(1));
      expect(s.trades.last.orderType, OrderType.market);
      expect(PortfolioEngine.reset(10000000).orders, isEmpty);
    });
  });

  test('worked example from TESTING.md', () {
    var s = start;
    expect(s.wallet.cashCents, 10000000);

    s = buy(s, 10 * sh, 10000);
    expect(s.wallet.cashCents, 9900000);
    expect(s.holdings['AAPL']!.quantity, 10 * sh);
    expect(s.holdings['AAPL']!.avgCostCents, 10000);

    s = buy(s, 10 * sh, 11000);
    expect(s.wallet.cashCents, 9790000);
    expect(s.holdings['AAPL']!.quantity, 20 * sh);
    expect(s.holdings['AAPL']!.avgCostCents, 10500);

    s = sell(s, 5 * sh, 12000);
    expect(s.wallet.cashCents, 9850000);
    expect(s.holdings['AAPL']!.quantity, 15 * sh);
    expect(s.holdings['AAPL']!.avgCostCents, 10500);
    expect(s.trades.last.realizedPnlCents, 7500);

    final sum = PortfolioEngine.summary(s, {'AAPL': 10000});
    expect(sum.unrealizedPnlCents, -7500);
    expect(sum.portfolioValueCents, 10000000);
  });
}
