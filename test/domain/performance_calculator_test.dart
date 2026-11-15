import 'package:flutter_test/flutter_test.dart';
import 'package:papertrade/domain/models/trade.dart';
import 'package:papertrade/domain/performance_calculator.dart';

var _n = 0;

Trade buy() => Trade(
  id: 'b${_n++}',
  symbol: 'AAPL',
  side: TradeSide.buy,
  quantity: 10000,
  priceCents: 10000,
  executedAt: DateTime(2026, 11, 15),
);

Trade sell(int pnl, [String symbol = 'AAPL']) => Trade(
  id: 's${_n++}',
  symbol: symbol,
  side: TradeSide.sell,
  quantity: 10000,
  priceCents: 10000,
  executedAt: DateTime(2026, 11, 15),
  realizedPnlCents: pnl,
);

PerformanceStats calc(List<Trade> trades) =>
    PerformanceCalculator.calculate(trades);

void main() {
  test('no trades: zeros and nulls', () {
    final s = calc([]);
    expect(s.totalRealizedPnlCents, 0);
    expect(s.tradeCount, 0);
    expect(s.sellCount, 0);
    expect(s.winCount, 0);
    expect(s.winRate, isNull);
    expect(s.averageWinCents, isNull);
    expect(s.averageLossCents, isNull);
    expect(s.bestTrade, isNull);
    expect(s.worstTrade, isNull);
  });

  test('only buys: counted as trades, no win/loss numbers', () {
    final s = calc([buy(), buy()]);
    expect(s.tradeCount, 2);
    expect(s.sellCount, 0);
    expect(s.totalRealizedPnlCents, 0);
    expect(s.winRate, isNull);
    expect(s.bestTrade, isNull);
  });

  test('total realized P&L sums sells only', () {
    expect(
      calc([buy(), sell(7500), sell(-2000), sell(0)]).totalRealizedPnlCents,
      5500,
    );
  });

  test('number of trades counts buys and sells', () {
    expect(calc([buy(), sell(1), buy(), sell(-1), sell(0)]).tradeCount, 5);
  });

  group('win rate', () {
    test('wins / sells × 100', () {
      final s = calc([buy(), sell(100), sell(-50), sell(200), sell(-1)]);
      expect(s.winCount, 2);
      expect(s.sellCount, 4);
      expect(s.winRate, closeTo(50, 1e-9));
    });

    test('a break-even sell is not a win but counts as a sell', () {
      final s = calc([sell(100), sell(0), sell(0)]);
      expect(s.winRate, closeTo(100 / 3, 1e-9));
    });

    test('all losses → 0%, all wins → 100%', () {
      expect(calc([sell(-1), sell(-2)]).winRate, 0);
      expect(calc([sell(1), sell(2)]).winRate, 100);
    });
  });

  group('average win', () {
    test('mean of positive sells only', () {
      expect(
        calc([sell(100), sell(300), sell(-999), sell(0)]).averageWinCents,
        200,
      );
    });

    test('rounds half up to whole cents', () {
      expect(calc([sell(1), sell(2)]).averageWinCents, 2); // 1.5 → 2
      expect(calc([sell(1), sell(1), sell(2)]).averageWinCents, 1); // 1.33
    });

    test('null without wins', () {
      expect(calc([sell(-5), sell(0)]).averageWinCents, isNull);
    });
  });

  group('average loss', () {
    test('mean of negative sells only, negative', () {
      expect(
        calc([sell(-100), sell(-300), sell(999), sell(0)]).averageLossCents,
        -200,
      );
    });

    test('rounds the size half up: -1.5¢ → -2¢', () {
      expect(calc([sell(-1), sell(-2)]).averageLossCents, -2);
    });

    test('null without losses', () {
      expect(calc([sell(5), sell(0)]).averageLossCents, isNull);
    });
  });

  group('best and worst trade', () {
    test('highest and lowest realized P&L', () {
      final best = sell(7500, 'MSFT');
      final worst = sell(-4000, 'TSLA');
      final s = calc([buy(), sell(100), best, worst, sell(-10)]);
      expect(s.bestTrade, same(best));
      expect(s.worstTrade, same(worst));
    });

    test('one sell is both best and worst', () {
      final only = sell(-300);
      final s = calc([buy(), only]);
      expect(s.bestTrade, same(only));
      expect(s.worstTrade, same(only));
    });

    test('ties keep the earliest trade', () {
      final first = sell(500);
      final s = calc([first, sell(500)]);
      expect(s.bestTrade, same(first));
      expect(s.worstTrade, same(first));
    });

    test('buys are never best or worst', () {
      final s = calc([buy(), sell(-1)]);
      expect(s.bestTrade!.side, TradeSide.sell);
    });
  });
}
