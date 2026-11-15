import 'holding.dart';
import 'pending_order.dart';
import 'trade.dart';
import 'wallet.dart';

/// Everything PortfolioEngine works on. Immutable: the engine returns a new
/// state instead of changing this one.
class PortfolioState {
  PortfolioState({
    required this.wallet,
    required this.startingCashCents,
    Map<String, Holding> holdings = const {},
    List<Trade> trades = const [],
    List<PendingOrder> orders = const [],
  }) : holdings = Map.unmodifiable(holdings),
       trades = List.unmodifiable(trades),
       orders = List.unmodifiable(orders);

  PortfolioState.initial([int startingCashCents = defaultStartingCashCents])
    : this(
        wallet: Wallet(cashCents: startingCashCents),
        startingCashCents: startingCashCents,
      );

  final Wallet wallet;
  // What the account started with; total return is measured against it.
  final int startingCashCents;
  final Map<String, Holding> holdings; // keyed by symbol
  final List<Trade> trades; // oldest first
  final List<PendingOrder> orders; // open limit/stop orders, oldest first

  // Reservations are derived from the open orders, never stored, so they
  // can't drift out of sync with them. Wallet cash still includes reserved
  // cash: it isn't spent until the order fills.
  int get reservedCashCents =>
      orders.fold(0, (sum, o) => sum + o.reservedCashCents);

  int get availableCashCents => wallet.cashCents - reservedCashCents;

  /// Held quantity not already promised to an open sell order.
  int availableQuantity(String symbol) {
    final held = holdings[symbol]?.quantity ?? 0;
    final reserved = orders
        .where((o) => o.symbol == symbol && o.side == TradeSide.sell)
        .fold(0, (sum, o) => sum + o.quantity);
    return held - reserved;
  }
}
