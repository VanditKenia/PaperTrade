import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/portfolio_repository.dart';
import '../../domain/models/portfolio_state.dart';
import '../../domain/models/portfolio_summary.dart';
import '../../domain/models/trade.dart';
import '../../domain/portfolio_engine.dart';
import '../watchlist/watchlist_provider.dart';

final portfolioProvider = NotifierProvider<PortfolioNotifier, PortfolioState>(
  PortfolioNotifier.new,
);

/// Wallet, holdings and trades. Every change goes engine → save → state.
class PortfolioNotifier extends Notifier<PortfolioState> {
  @override
  PortfolioState build() => ref.watch(portfolioRepositoryProvider).load();

  /// Buys at [priceCents], the price the user saw when confirming. Never
  /// reads a price provider itself: those may (indirectly) depend on this
  /// notifier, which would be a circular dependency.
  ///
  /// Throws TradeError if the engine rejects the trade, StorageError if the
  /// save fails; in both cases state is unchanged.
  Future<Trade> buy(String symbol, int quantity, {required int? priceCents}) =>
      _apply(
        (s) => PortfolioEngine.buy(
          s,
          symbol: symbol,
          quantity: quantity,
          priceCents: priceCents,
        ),
      );

  Future<Trade> sell(String symbol, int quantity, {required int? priceCents}) =>
      _apply(
        (s) => PortfolioEngine.sell(
          s,
          symbol: symbol,
          quantity: quantity,
          priceCents: priceCents,
        ),
      );

  Future<void> reset() async {
    final next = PortfolioEngine.reset();
    await ref.read(portfolioRepositoryProvider).save(next);
    state = next;
  }

  Future<Trade> _apply(PortfolioState Function(PortfolioState) trade) async {
    final next = trade(state); // throws before anything is saved
    // Save first, then publish: if the write fails, the screen keeps showing
    // what is actually on disk.
    await ref.read(portfolioRepositoryProvider).save(next);
    state = next;
    return next.trades.last;
  }
}

/// Totals for the portfolio header. Recomputes whenever a held symbol's
/// price changes — at most every 500 ms thanks to the throttled stream.
final portfolioSummaryProvider = Provider<PortfolioSummary>((ref) {
  final portfolio = ref.watch(portfolioProvider);
  final prices = <String, int>{
    for (final symbol in portfolio.holdings.keys)
      symbol: ?ref.watch(latestPriceProvider(symbol)),
  };
  return PortfolioEngine.summary(portfolio, prices);
});
