enum TradeSide { buy, sell }

/// How an order executes: now at the market price, or later when the
/// price reaches a limit or stop.
enum OrderType { market, limit, stopLoss }

/// An executed (filled) order. Trades are never edited once created.
class Trade {
  const Trade({
    required this.id,
    required this.symbol,
    required this.side,
    required this.quantity,
    required this.priceCents,
    required this.executedAt,
    this.realizedPnlCents,
    this.orderType = OrderType.market,
  });

  final String id;
  final String symbol;
  final TradeSide side;
  final int quantity; // units of 1/10,000 share (see quantity.dart)
  final int priceCents; // fill price per share
  final DateTime executedAt;
  final int? realizedPnlCents; // only for sells
  final OrderType orderType; // how it was filled
}
