import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertrade/data/portfolio_repository.dart';
import 'package:papertrade/data/storage_error.dart';
import 'package:papertrade/domain/models/trade.dart';
import 'package:papertrade/domain/models/wallet.dart';
import 'package:papertrade/domain/trade_errors.dart';
import 'package:papertrade/features/portfolio/portfolio_provider.dart';
import 'package:papertrade/features/watchlist/watchlist_provider.dart';
import 'package:papertrade/domain/quantity.dart';

import '../../fakes.dart';

void main() {
  late FakePortfolioRepository repo;
  late ProviderContainer container;
  int? price;

  setUp(() {
    repo = FakePortfolioRepository();
    price = 10000;
    container = ProviderContainer.test(
      overrides: [
        portfolioRepositoryProvider.overrideWithValue(repo),
        latestPriceProvider('AAPL').overrideWith((_) => price),
      ],
    );
  });

  PortfolioNotifier notifier() => container.read(portfolioProvider.notifier);

  test('buy executes at the given price, saves, then updates state', () async {
    final trade = await notifier().buy(
      'AAPL',
      5 * unitsPerShare,
      priceCents: price,
    );

    expect(trade.side, TradeSide.buy);
    expect(trade.priceCents, 10000);
    expect(repo.saves, 1);
    expect(repo.saved.holdings['AAPL']!.quantity, 5 * unitsPerShare);
    expect(container.read(portfolioProvider).wallet.cashCents, 9950000);
  });

  test('rejected trade saves nothing and leaves state unchanged', () async {
    await expectLater(
      notifier().sell('AAPL', 1 * unitsPerShare, priceCents: price),
      throwsA(isA<InsufficientShares>()),
    );
    expect(repo.saves, 0);
    expect(container.read(portfolioProvider).trades, isEmpty);
  });

  test('no price → PriceUnavailable', () async {
    await expectLater(
      notifier().buy('AAPL', 1 * unitsPerShare, priceCents: null),
      throwsA(isA<PriceUnavailable>()),
    );
  });

  test('failed save leaves state matching what is on disk', () async {
    repo.failSaves = true;
    await expectLater(
      notifier().buy('AAPL', 1 * unitsPerShare, priceCents: price),
      throwsA(isA<StorageError>()),
    );
    expect(
      container.read(portfolioProvider).wallet.cashCents,
      defaultStartingCashCents,
    );
  });

  test('reset saves a fresh account with the chosen balance', () async {
    await notifier().buy('AAPL', 5 * unitsPerShare, priceCents: price);
    await notifier().reset(2500000);
    expect(repo.saved.holdings, isEmpty);
    expect(repo.saved.startingCashCents, 2500000);
    expect(container.read(portfolioProvider).wallet.cashCents, 2500000);
  });

  test('invalid reset amount changes nothing', () async {
    await notifier().buy('AAPL', 5 * unitsPerShare, priceCents: price);
    final saves = repo.saves;
    await expectLater(
      notifier().reset(50),
      throwsA(isA<InvalidStartingBalance>()),
    );
    expect(repo.saves, saves);
    expect(container.read(portfolioProvider).holdings, isNotEmpty);
  });

  test('summary recomputes when a held price changes', () async {
    await notifier().buy(
      'AAPL',
      10 * unitsPerShare,
      priceCents: price,
    ); // at $100
    expect(container.read(portfolioSummaryProvider).unrealizedPnlCents, 0);

    price = 11000;
    container.invalidate(latestPriceProvider('AAPL'));
    final s = container.read(portfolioSummaryProvider);
    expect(s.unrealizedPnlCents, 10000);
    expect(s.investedCents, 100000);
    expect(s.portfolioValueCents, 10000000 + 10000);
  });
}
