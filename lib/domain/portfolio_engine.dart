import 'models/holding.dart';
import 'models/portfolio_state.dart';
import 'models/portfolio_summary.dart';
import 'models/trade.dart';
import 'models/wallet.dart';
import 'trade_errors.dart';

/// Pure buy/sell/P&L rules (TRD.md §4). Every method takes a state and
/// returns a new one, or throws a [TradeError] leaving the input untouched.
abstract final class PortfolioEngine {
  static PortfolioState buy(
    PortfolioState state, {
    required String symbol,
    required int quantity,
    required int? priceCents,
    DateTime? now,
  }) {
    _checkOrder(quantity, priceCents);
    final price = priceCents!;
    final cost = quantity * price;
    if (cost > state.wallet.cashCents) throw const InsufficientFunds();

    final old = state.holdings[symbol];
    final Holding holding;
    if (old == null) {
      holding = Holding(
        symbol: symbol,
        quantity: quantity,
        avgCostCents: price,
      );
    } else {
      final newQty = old.quantity + quantity;
      final totalCost = old.quantity * old.avgCostCents + cost;
      // Integer division rounding half up: adding newQty/2 before dividing
      // keeps everything in int cents (no double).
      final newAvg = (totalCost + newQty ~/ 2) ~/ newQty;
      holding = Holding(symbol: symbol, quantity: newQty, avgCostCents: newAvg);
    }

    return PortfolioState(
      wallet: Wallet(cashCents: state.wallet.cashCents - cost),
      holdings: {...state.holdings, symbol: holding},
      trades: [
        ...state.trades,
        _trade(state, symbol, TradeSide.buy, quantity, price, now),
      ],
    );
  }

  static PortfolioState sell(
    PortfolioState state, {
    required String symbol,
    required int quantity,
    required int? priceCents,
    DateTime? now,
  }) {
    _checkOrder(quantity, priceCents);
    final price = priceCents!;
    final old = state.holdings[symbol];
    if (old == null || quantity > old.quantity) {
      throw const InsufficientShares();
    }

    // Avg cost is the cost basis of the shares still held, so selling
    // doesn't change it — the gain/loss is "realized" into the trade instead.
    final realizedPnl = (price - old.avgCostCents) * quantity;
    final remaining = old.quantity - quantity;
    final holdings = {...state.holdings}..remove(symbol);
    if (remaining > 0) {
      holdings[symbol] = Holding(
        symbol: symbol,
        quantity: remaining,
        avgCostCents: old.avgCostCents,
      );
    }

    return PortfolioState(
      wallet: Wallet(cashCents: state.wallet.cashCents + quantity * price),
      holdings: holdings,
      trades: [
        ...state.trades,
        _trade(
          state,
          symbol,
          TradeSide.sell,
          quantity,
          price,
          now,
          realizedPnl,
        ),
      ],
    );
  }

  static PortfolioState reset() => PortfolioState.initial();

  static int marketValue(Holding h, int livePriceCents) =>
      h.quantity * livePriceCents;

  static int unrealizedPnl(Holding h, int livePriceCents) =>
      (livePriceCents - h.avgCostCents) * h.quantity;

  static double unrealizedPnlPercent(Holding h, int livePriceCents) =>
      (livePriceCents - h.avgCostCents) / h.avgCostCents * 100;

  /// [livePrices] maps symbol → price in cents.
  static PortfolioSummary summary(
    PortfolioState state,
    Map<String, int> livePrices,
  ) {
    var marketValueSum = 0;
    var unrealizedSum = 0;
    for (final h in state.holdings.values) {
      // shortcut: a symbol with no live price yet is valued at avg cost
      // (P&L 0); upgrade to the last quote price once quotes are cached.
      final price = livePrices[h.symbol] ?? h.avgCostCents;
      marketValueSum += marketValue(h, price);
      unrealizedSum += unrealizedPnl(h, price);
    }
    final value = state.wallet.cashCents + marketValueSum;
    final totalReturn = value - startingCashCents;
    return PortfolioSummary(
      cashCents: state.wallet.cashCents,
      marketValueCents: marketValueSum,
      unrealizedPnlCents: unrealizedSum,
      portfolioValueCents: value,
      totalReturnCents: totalReturn,
      totalReturnPercent: totalReturn / startingCashCents * 100,
    );
  }

  static void _checkOrder(int quantity, int? priceCents) {
    if (quantity < 1) throw const InvalidQuantity();
    if (priceCents == null || priceCents <= 0) throw const PriceUnavailable();
  }

  static Trade _trade(
    PortfolioState state,
    String symbol,
    TradeSide side,
    int quantity,
    int priceCents,
    DateTime? now, [
    int? realizedPnlCents,
  ]) {
    final executedAt = now ?? DateTime.now();
    return Trade(
      // Timestamp + trade count stays unique even for two trades in the same
      // microsecond, without adding a uuid dependency.
      id: '${executedAt.microsecondsSinceEpoch}-${state.trades.length}',
      symbol: symbol,
      side: side,
      quantity: quantity,
      priceCents: priceCents,
      executedAt: executedAt,
      realizedPnlCents: realizedPnlCents,
    );
  }
}
