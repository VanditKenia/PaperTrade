import 'models/holding.dart';
import 'models/pending_order.dart';
import 'models/portfolio_state.dart';
import 'models/portfolio_summary.dart';
import 'models/trade.dart';
import 'models/wallet.dart';
import 'quantity.dart';
import 'trade_errors.dart';

/// Pure buy/sell/P&L rules (TRD.md §4). Every method takes a state and
/// returns a new one, or throws a [TradeError] leaving the input untouched.
abstract final class PortfolioEngine {
  static const minStartingCashCents = 10000; // $100
  static const maxStartingCashCents = 1000000000; // $10,000,000

  /// Whole dollars within the bounds. Whole dollars keep the presets and
  /// the typed amount simple; cents add nothing to a practice account.
  static bool isValidStartingCash(int cents) =>
      cents % 100 == 0 &&
      cents >= minStartingCashCents &&
      cents <= maxStartingCashCents;

  static PortfolioState buy(
    PortfolioState state, {
    required String symbol,
    required int quantity,
    required int? priceCents,
    DateTime? now,
  }) => _buy(state, symbol, quantity, priceCents, now, OrderType.market);

  static PortfolioState sell(
    PortfolioState state, {
    required String symbol,
    required int quantity,
    required int? priceCents,
    DateTime? now,
  }) => _sell(state, symbol, quantity, priceCents, now, OrderType.market);

  /// Opens a limit or stop-loss order. Nothing is bought or sold yet, but
  /// the order reserves what it needs (cash for a buy, shares for a sell),
  /// so a later trade or order can't spend it twice.
  static PortfolioState placeOrder(
    PortfolioState state, {
    required String symbol,
    required TradeSide side,
    required OrderType type,
    required int quantity,
    required int? triggerPriceCents,
    DateTime? now,
  }) {
    // The UI never offers these; reaching here is a bug, not a user error.
    if (type == OrderType.market ||
        (type == OrderType.stopLoss && side == TradeSide.buy)) {
      throw ArgumentError('Not a pending order type: $side $type');
    }
    if (quantity < 1) throw const InvalidQuantity();
    final price = triggerPriceCents;
    if (price == null || price <= 0) throw const InvalidOrderPrice();
    if (costCents(quantity, price) < 1) throw const OrderTooSmall();
    if (side == TradeSide.buy) {
      if (costCents(quantity, price) > state.availableCashCents) {
        throw const InsufficientFunds();
      }
    } else if (quantity > state.availableQuantity(symbol)) {
      throw const InsufficientShares();
    }

    final createdAt = now ?? DateTime.now();
    final order = PendingOrder(
      // Trade and order counts keep ids unique within one microsecond.
      id:
          'o${createdAt.microsecondsSinceEpoch}-'
          '${state.trades.length}-${state.orders.length}',
      symbol: symbol,
      side: side,
      type: type,
      quantity: quantity,
      triggerPriceCents: price,
      createdAt: createdAt,
    );
    return _copy(state, orders: [...state.orders, order]);
  }

  /// Removes an open order, releasing its reservation.
  static PortfolioState cancelOrder(PortfolioState state, String orderId) {
    _order(state, orderId);
    return _copy(state, orders: _without(state, orderId));
  }

  /// Executes an open order at [priceCents], the tick that triggered it.
  /// The reservation is released first, then the trade runs through the
  /// same rules as a market trade, so cash and basis math can't differ.
  static PortfolioState fillOrder(
    PortfolioState state, {
    required String orderId,
    required int priceCents,
    DateTime? now,
  }) {
    final order = _order(state, orderId);
    if (priceCents <= 0) throw const PriceUnavailable();
    if (!order.triggersAt(priceCents)) throw const OrderNotTriggered();
    final released = _copy(state, orders: _without(state, orderId));
    return order.side == TradeSide.buy
        ? _buy(
            released,
            order.symbol,
            order.quantity,
            priceCents,
            now,
            order.type,
          )
        : _sell(
            released,
            order.symbol,
            order.quantity,
            priceCents,
            now,
            order.type,
          );
  }

  static PortfolioState _buy(
    PortfolioState state,
    String symbol,
    int quantity,
    int? priceCents,
    DateTime? now,
    OrderType type,
  ) {
    _checkOrder(quantity, priceCents);
    final price = priceCents!;
    final cost = costCents(quantity, price);
    // A tiny fraction can round to 0 cents; never hand out free shares.
    if (cost < 1) throw const OrderTooSmall();
    // Cash reserved by open limit buys isn't available.
    if (cost > state.availableCashCents) throw const InsufficientFunds();

    // Adding the exact cost to the basis keeps the weighted average exact:
    // avg = basis / qty is computed only for display.
    final old = state.holdings[symbol];
    final holding = Holding(
      symbol: symbol,
      quantity: (old?.quantity ?? 0) + quantity,
      costBasisCents: (old?.costBasisCents ?? 0) + cost,
    );

    return _copy(
      state,
      wallet: Wallet(cashCents: state.wallet.cashCents - cost),
      holdings: {...state.holdings, symbol: holding},
      trades: [
        ...state.trades,
        _trade(state, symbol, TradeSide.buy, quantity, price, now, type),
      ],
    );
  }

  static PortfolioState _sell(
    PortfolioState state,
    String symbol,
    int quantity,
    int? priceCents,
    DateTime? now,
    OrderType type,
  ) {
    _checkOrder(quantity, priceCents);
    final price = priceCents!;
    final old = state.holdings[symbol];
    // Shares promised to open sell orders aren't available.
    if (old == null || quantity > state.availableQuantity(symbol)) {
      throw const InsufficientShares();
    }

    final proceeds = costCents(quantity, price);
    if (proceeds < 1) throw const OrderTooSmall();
    final soldBasis = _soldBasis(old, quantity);
    final remaining = old.quantity - quantity;
    final holdings = {...state.holdings}..remove(symbol);
    if (remaining > 0) {
      holdings[symbol] = Holding(
        symbol: symbol,
        quantity: remaining,
        costBasisCents: old.costBasisCents - soldBasis,
      );
    }

    return _copy(
      state,
      wallet: Wallet(cashCents: state.wallet.cashCents + proceeds),
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
          type,
          proceeds - soldBasis,
        ),
      ],
    );
  }

  /// Fresh account with [startingCashCents]: no holdings, trades or orders.
  static PortfolioState reset(int startingCashCents) {
    if (!isValidStartingCash(startingCashCents)) {
      throw const InvalidStartingBalance();
    }
    return PortfolioState.initial(startingCashCents);
  }

  /// What selling [quantity] of [h] at [priceCents] would realize; the
  /// order sheet preview uses it so it matches the engine to the cent.
  static int realizedPnl(Holding h, int quantity, int priceCents) =>
      costCents(quantity, priceCents) - _soldBasis(h, quantity);

  static int marketValue(Holding h, int livePriceCents) =>
      costCents(h.quantity, livePriceCents);

  static int unrealizedPnl(Holding h, int livePriceCents) =>
      marketValue(h, livePriceCents) - h.costBasisCents;

  static double unrealizedPnlPercent(Holding h, int livePriceCents) =>
      // A sub-cent position can round its basis to 0; avoid dividing by it.
      h.costBasisCents == 0
      ? 0
      : unrealizedPnl(h, livePriceCents) / h.costBasisCents * 100;

  /// [livePrices] maps symbol → latest price in cents (live or quote).
  static PortfolioSummary summary(
    PortfolioState state,
    Map<String, int> livePrices,
  ) {
    var marketValueSum = 0;
    var unrealizedSum = 0;
    var investedSum = 0;
    for (final h in state.holdings.values) {
      // A symbol with no price at all (no tick, no quote) is valued at its
      // cost, i.e. P&L 0, rather than 0, which would show a fake total loss.
      final price = livePrices[h.symbol];
      final worth = price == null ? h.costBasisCents : marketValue(h, price);
      investedSum += h.costBasisCents;
      marketValueSum += worth;
      unrealizedSum += worth - h.costBasisCents;
    }
    final value = state.wallet.cashCents + marketValueSum;
    final start = state.startingCashCents;
    final totalReturn = value - start;
    return PortfolioSummary(
      cashCents: state.wallet.cashCents,
      investedCents: investedSum,
      marketValueCents: marketValueSum,
      unrealizedPnlCents: unrealizedSum,
      portfolioValueCents: value,
      totalReturnCents: totalReturn,
      totalReturnPercent: totalReturn / start * 100,
      startingCashCents: start,
    );
  }

  /// The part of the cost basis that leaves with a sell. Proportional to the
  /// quantity sold (so avg cost doesn't change), and selling everything takes
  /// the whole basis, so rounding never leaves cents behind.
  static int _soldBasis(Holding h, int quantity) => quantity == h.quantity
      ? h.costBasisCents
      : mulDivHalfUp(h.costBasisCents, quantity, h.quantity);

  static PendingOrder _order(PortfolioState state, String orderId) =>
      state.orders.where((o) => o.id == orderId).firstOrNull ??
      (throw const OrderNotFound());

  static List<PendingOrder> _without(PortfolioState state, String orderId) => [
    for (final o in state.orders)
      if (o.id != orderId) o,
  ];

  static PortfolioState _copy(
    PortfolioState state, {
    Wallet? wallet,
    Map<String, Holding>? holdings,
    List<Trade>? trades,
    List<PendingOrder>? orders,
  }) => PortfolioState(
    wallet: wallet ?? state.wallet,
    startingCashCents: state.startingCashCents,
    holdings: holdings ?? state.holdings,
    trades: trades ?? state.trades,
    orders: orders ?? state.orders,
  );

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
    DateTime? now,
    OrderType type, [
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
      orderType: type,
    );
  }
}
