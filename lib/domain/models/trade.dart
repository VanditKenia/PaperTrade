enum TradeSide { buy, sell }

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
  });

  final String id;
  final String symbol;
  final TradeSide side;
  final int quantity;
  final int priceCents; // fill price per share
  final DateTime executedAt;
  final int? realizedPnlCents; // only for sells
}
