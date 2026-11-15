enum AlertDirection { above, below }

/// "Tell me when AAPL rises above $200" (or falls below). Fires once, then
/// stays in the list as triggered until deleted.
class PriceAlert {
  const PriceAlert({
    required this.id,
    required this.symbol,
    required this.direction,
    required this.targetCents,
    required this.createdAt,
    this.triggeredAt,
    this.triggeredPriceCents,
  });

  final String id;
  final String symbol;
  final AlertDirection direction;
  final int targetCents;
  final DateTime createdAt;
  final DateTime? triggeredAt; // null while waiting
  final int? triggeredPriceCents; // the tick that fired it

  bool get isTriggered => triggeredAt != null;

  PriceAlert triggered(int priceCents, DateTime at) => PriceAlert(
    id: id,
    symbol: symbol,
    direction: direction,
    targetCents: targetCents,
    createdAt: createdAt,
    triggeredAt: at,
    triggeredPriceCents: priceCents,
  );
}
