import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertrade/data/portfolio_repository.dart';
import 'package:papertrade/data/value_history_repository.dart';
import 'package:papertrade/domain/models/trade.dart';
import 'package:papertrade/domain/quantity.dart';
import 'package:papertrade/features/portfolio/portfolio_provider.dart';
import 'package:papertrade/features/stats/stats_provider.dart';
import 'package:papertrade/features/watchlist/watchlist_provider.dart';

import '../../fakes.dart';

void main() {
  late FakeValueHistoryRepository history;
  late ProviderContainer container;
  int? price;

  // Starts the recorder like AppShell does. With [async], the snapshot
  // clock follows fake time.
  void start([FakeAsync? async]) {
    final t0 = DateTime(2026, 11, 15, 10);
    history = FakeValueHistoryRepository();
    price = 10000;
    container = ProviderContainer.test(
      overrides: [
        portfolioRepositoryProvider.overrideWithValue(
          FakePortfolioRepository(),
        ),
        valueHistoryRepositoryProvider.overrideWithValue(history),
        if (async != null)
          valueHistoryProvider.overrideWith(
            () => ValueHistoryNotifier(clock: () => t0.add(async.elapsed)),
          ),
        latestPriceProvider('AAPL').overrideWith((_) => price),
      ],
    );
    container.listen(snapshotRecorderProvider, (_, _) {});
  }

  List<int> values() =>
      container.read(valueHistoryProvider).map((s) => s.valueCents).toList();

  test('records once on open', () {
    fakeAsync((async) {
      start(async);
      async.flushMicrotasks();
      expect(values(), [10000000]);
      expect(history.saved, hasLength(1)); // persisted
      container.dispose();
    });
  });

  test('records every 5 minutes while open, not more often', () {
    fakeAsync((async) {
      start(async);
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 4));
      expect(values(), hasLength(1));
      async.elapse(const Duration(minutes: 1));
      expect(values(), hasLength(2));
      async.elapse(const Duration(minutes: 30));
      expect(values(), hasLength(8)); // 0, 5, 10, … 35
      container.dispose();
    });
  });

  test('records on every trade, with the value after it', () {
    fakeAsync((async) {
      start(async);
      async.flushMicrotasks();
      final portfolio = container.read(portfolioProvider.notifier);
      portfolio.buy('AAPL', 10 * unitsPerShare, priceCents: 10000);
      async.flushMicrotasks();
      // Fill at $120 while holdings are valued at the $100 market price.
      portfolio.sell('AAPL', 5 * unitsPerShare, priceCents: 12000);
      async.flushMicrotasks();

      // Open, buy (value unchanged), sell (+$100 realized).
      expect(values(), [10000000, 10000000, 10010000]);
      container.dispose();
    });
  });

  test('a reset clears the history and starts from the new balance', () {
    fakeAsync((async) {
      start(async);
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 10));
      expect(values(), hasLength(3));

      container.read(portfolioProvider.notifier).reset(2500000);
      async.flushMicrotasks();
      expect(values(), [2500000]);
      expect(history.saved.single.valueCents, 2500000);
      container.dispose();
    });
  });

  test('placing an order is not a trade: nothing recorded', () {
    fakeAsync((async) {
      start(async);
      async.flushMicrotasks();
      container
          .read(portfolioProvider.notifier)
          .placeOrder(
            symbol: 'AAPL',
            side: TradeSide.buy,
            type: OrderType.limit,
            quantity: unitsPerShare,
            triggerPriceCents: 9000,
          );
      async.flushMicrotasks();
      expect(container.read(portfolioProvider).orders, hasLength(1));
      expect(values(), hasLength(1)); // only the one from opening
      container.dispose();
    });
  });

  test('performanceStatsProvider follows the trades', () async {
    start();
    await container
        .read(portfolioProvider.notifier)
        .buy('AAPL', 10 * unitsPerShare, priceCents: 10000);
    await container
        .read(portfolioProvider.notifier)
        .sell('AAPL', 5 * unitsPerShare, priceCents: 11000);
    final s = container.read(performanceStatsProvider);
    expect(s.tradeCount, 2);
    expect(s.totalRealizedPnlCents, 5000);
    expect(s.winRate, 100);
  });
}
