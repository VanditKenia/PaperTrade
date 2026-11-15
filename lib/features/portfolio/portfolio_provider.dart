import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/portfolio_repository.dart';
import '../../domain/models/pending_order.dart';
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
  // Tail of the queue of changes; see _serial.
  Future<void> _last = Future.value();

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

  /// Opens a limit/stop order and reserves cash or shares for it. Throws
  /// like [buy].
  Future<PendingOrder> placeOrder({
    required String symbol,
    required TradeSide side,
    required OrderType type,
    required int quantity,
    required int? triggerPriceCents,
  }) async {
    final next = await _save(
      (s) => PortfolioEngine.placeOrder(
        s,
        symbol: symbol,
        side: side,
        type: type,
        quantity: quantity,
        triggerPriceCents: triggerPriceCents,
      ),
    );
    return next.orders.last;
  }

  /// Throws OrderNotFound if it already filled or was cancelled.
  Future<void> cancelOrder(String orderId) =>
      _save((s) => PortfolioEngine.cancelOrder(s, orderId));

  /// Called by orderMatcherProvider with the tick price that triggered the
  /// order; like [buy], this notifier never reads prices itself.
  Future<Trade> fillOrder(String orderId, {required int priceCents}) => _apply(
    (s) =>
        PortfolioEngine.fillOrder(s, orderId: orderId, priceCents: priceCents),
  );

  /// Throws InvalidStartingBalance for a bad amount, StorageError if the
  /// save fails; state is unchanged in both cases.
  Future<void> reset(int startingCashCents) =>
      _save((_) => PortfolioEngine.reset(startingCashCents));

  Future<Trade> _apply(PortfolioState Function(PortfolioState) trade) async =>
      (await _save(trade)).trades.last;

  Future<PortfolioState> _save(
    PortfolioState Function(PortfolioState) change,
  ) => _serial(() async {
    final next = change(state); // throws before anything is saved
    // Save first, then publish: if the write fails, the screen keeps
    // showing what is actually on disk.
    await ref.read(portfolioRepositoryProvider).save(next);
    state = next;
    return next;
  });

  /// Runs changes one after another. A fill from the matcher and a tap by
  /// the user can overlap while a save is in flight; each must start from
  /// the state the previous one saved, or one would overwrite the other.
  Future<T> _serial<T>(Future<T> Function() op) {
    final result = _last.then((_) => op());
    // The next change waits for this one whether it succeeds or fails.
    _last = result.then((_) {}, onError: (_) {});
    return result;
  }
}

/// True until a portfolio has been saved: first launch shows the
/// starting-balance screen. Watches the portfolio so it flips to false as
/// soon as onboarding's reset() has saved.
final needsOnboardingProvider = Provider<bool>((ref) {
  ref.watch(portfolioProvider);
  return !ref.read(portfolioRepositoryProvider).hasSaved;
});

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
