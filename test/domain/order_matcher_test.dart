import 'package:flutter_test/flutter_test.dart';
import 'package:papertrade/domain/models/pending_order.dart';
import 'package:papertrade/domain/models/trade.dart';
import 'package:papertrade/domain/order_matcher.dart';

PendingOrder order(
  TradeSide side,
  OrderType type,
  int trigger, {
  String id = 'o1',
  String symbol = 'AAPL',
}) => PendingOrder(
  id: id,
  symbol: symbol,
  side: side,
  type: type,
  quantity: 10000,
  triggerPriceCents: trigger,
  createdAt: DateTime(2026, 11, 15),
);

void main() {
  group('trigger rules', () {
    test('limit buy fills at or below the limit', () {
      final o = order(TradeSide.buy, OrderType.limit, 18000);
      expect(o.triggersAt(17999), isTrue);
      expect(o.triggersAt(18000), isTrue);
      expect(o.triggersAt(18001), isFalse);
    });

    test('limit sell fills at or above the limit', () {
      final o = order(TradeSide.sell, OrderType.limit, 20000);
      expect(o.triggersAt(20001), isTrue);
      expect(o.triggersAt(20000), isTrue);
      expect(o.triggersAt(19999), isFalse);
    });

    test('stop-loss sell fills at or below the stop', () {
      final o = order(TradeSide.sell, OrderType.stopLoss, 17000);
      expect(o.triggersAt(16999), isTrue);
      expect(o.triggersAt(17000), isTrue);
      expect(o.triggersAt(17001), isFalse);
    });

    test('only limit buys reserve cash, at the limit price', () {
      expect(
        order(TradeSide.buy, OrderType.limit, 18000).reservedCashCents,
        18000,
      );
      expect(
        order(TradeSide.sell, OrderType.limit, 18000).reservedCashCents,
        0,
      );
    });
  });

  test('ticks are only the prices that changed', () {
    expect(
      OrderMatcher.ticks(
        {'AAPL': 100, 'MSFT': 200},
        {'AAPL': 100, 'MSFT': 201, 'TSLA': 300},
      ),
      {'MSFT': 201, 'TSLA': 300},
    );
    expect(OrderMatcher.ticks({}, {'AAPL': 100}), {'AAPL': 100});
  });

  group('triggered', () {
    test('returns triggered orders oldest first with the tick price', () {
      final a = order(TradeSide.buy, OrderType.limit, 18000, id: 'a');
      final b = order(TradeSide.sell, OrderType.stopLoss, 17500, id: 'b');
      final c = order(TradeSide.sell, OrderType.limit, 19000, id: 'c');
      final hits = OrderMatcher.triggered([a, b, c], {'AAPL': 17400});
      expect(hits.map((h) => h.$1.id), ['a', 'b']);
      expect(hits.map((h) => h.$2), [17400, 17400]);
    });

    test('ignores orders for symbols without a tick', () {
      final o = order(TradeSide.buy, OrderType.limit, 99999, symbol: 'MSFT');
      expect(OrderMatcher.triggered([o], {'AAPL': 1}), isEmpty);
    });
  });
}
