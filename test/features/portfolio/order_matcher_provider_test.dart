import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertrade/data/portfolio_repository.dart';
import 'package:papertrade/domain/models/portfolio_state.dart';
import 'package:papertrade/domain/models/trade.dart';
import 'package:papertrade/domain/portfolio_engine.dart';
import 'package:papertrade/domain/quantity.dart';
import 'package:papertrade/features/portfolio/order_matcher_provider.dart';
import 'package:papertrade/features/portfolio/portfolio_provider.dart';
import 'package:papertrade/features/watchlist/watchlist_provider.dart';

import '../../fakes.dart';

const sh = unitsPerShare;

/// Saves only when [gate] completes, to hold a save "in flight".
class _SlowRepository extends FakePortfolioRepository {
  _SlowRepository();

  Completer<void> gate = Completer<void>();

  @override
  Future<void> save(PortfolioState state) async {
    await gate.future;
    return super.save(state);
  }
}

void main() {
  late StreamController<Map<String, int>> prices;
  late FakePortfolioRepository repo;
  late ProviderContainer container;

  void start([FakePortfolioRepository? repository]) {
    repo = repository ?? FakePortfolioRepository();
    prices = StreamController<Map<String, int>>();
    addTearDown(prices.close);
    container = ProviderContainer.test(
      overrides: [
        portfolioRepositoryProvider.overrideWithValue(repo),
        livePricesProvider.overrideWith((_) => prices.stream),
      ],
    );
    container.listen(orderMatcherProvider, (_, _) {});
  }

  PortfolioNotifier portfolio() => container.read(portfolioProvider.notifier);
  PortfolioState state() => container.read(portfolioProvider);

  /// Sends one throttled price snapshot and lets the fills finish.
  Future<void> tick(Map<String, int> snapshot) async {
    prices.add(snapshot);
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> placeLimitBuy(int qty, int limit) => portfolio().placeOrder(
    symbol: 'AAPL',
    side: TradeSide.buy,
    type: OrderType.limit,
    quantity: qty,
    triggerPriceCents: limit,
  );

  test('limit buy fills at the triggering tick price, not before', () async {
    start();
    await placeLimitBuy(10 * sh, 18000);

    await tick({'AAPL': 18100});
    expect(state().orders, hasLength(1));

    await tick({'AAPL': 17950});
    expect(state().orders, isEmpty);
    final t = state().trades.single;
    expect(t.priceCents, 17950);
    expect(t.orderType, OrderType.limit);
    expect(state().wallet.cashCents, 10000000 - 179500);
    expect(repo.saved.trades, hasLength(1)); // persisted
  });

  test('stop-loss sells when the price falls to the stop', () async {
    start(
      FakePortfolioRepository(
        PortfolioEngine.buy(
          PortfolioState.initial(),
          symbol: 'AAPL',
          quantity: 10 * sh,
          priceCents: 10000,
        ),
      ),
    );
    await portfolio().placeOrder(
      symbol: 'AAPL',
      side: TradeSide.sell,
      type: OrderType.stopLoss,
      quantity: 5 * sh,
      triggerPriceCents: 9000,
    );

    await tick({'AAPL': 9100});
    expect(state().holdings['AAPL']!.quantity, 10 * sh);

    await tick({'AAPL': 8950});
    final t = state().trades.last;
    expect(t.orderType, OrderType.stopLoss);
    expect(t.priceCents, 8950);
    expect(t.realizedPnlCents, -5250);
    expect(state().holdings['AAPL']!.quantity, 5 * sh);
  });

  test('an unchanged price is not a tick: no fill at a stale price', () async {
    start();
    await tick({'AAPL': 17000});
    await placeLimitBuy(sh, 18000);

    // Another symbol ticks; AAPL's 170.00 in the snapshot is old news.
    await tick({'AAPL': 17000, 'MSFT': 40000});
    expect(state().orders, hasLength(1));

    await tick({'AAPL': 17010, 'MSFT': 40000});
    expect(state().trades.single.priceCents, 17010);
  });

  test('a cancelled order never fills', () async {
    start();
    await placeLimitBuy(sh, 18000);
    await portfolio().cancelOrder(state().orders.single.id);
    await tick({'AAPL': 100});
    expect(state().trades, isEmpty);
  });

  test('one fill per order even if ticks arrive while it saves', () async {
    final slow = _SlowRepository();
    start(slow);
    slow.gate.complete();
    await placeLimitBuy(sh, 18000);
    slow.gate = Completer<void>();

    await tick({'AAPL': 17900});
    await tick({'AAPL': 17800}); // also triggers; fill still saving
    slow.gate.complete();
    await tick({'AAPL': 17800});

    expect(state().trades.single.priceCents, 17900);
  });

  test('a fill and a user trade at the same time both survive', () async {
    final slow = _SlowRepository();
    start(slow);
    slow.gate.complete();
    await placeLimitBuy(sh, 18000);
    slow.gate = Completer<void>();

    await tick({'AAPL': 17900}); // fill waits on the save
    final userBuy = portfolio().buy('AAPL', sh, priceCents: 17900);
    slow.gate.complete();
    await userBuy;
    await tick({'AAPL': 17900});

    expect(state().trades.map((t) => t.orderType), [
      OrderType.limit,
      OrderType.market,
    ]);
    expect(state().holdings['AAPL']!.quantity, 2 * sh);
    expect(repo.saved.trades, hasLength(2));
  });

  test('an order that can no longer fill is cancelled, not retried', () async {
    start();
    await placeLimitBuy(1, 5000); // 0.0001 × $50 = 1¢
    await tick({'AAPL': 4000}); // 0.0001 × $40 rounds to 0¢
    expect(state().trades, isEmpty);
    expect(state().orders, isEmpty);
    expect(state().reservedCashCents, 0);
  });
}
