import '../quantity.dart';
import 'trade.dart';

/// A limit or stop-loss order waiting for its price. It holds back
/// ("reserves") cash or shares until it fills or is cancelled.
class PendingOrder {
  const PendingOrder({
    required this.id,
    required this.symbol,
    required this.side,
    required this.type,
    required this.quantity,
    required this.triggerPriceCents,
    required this.createdAt,
  });

  final String id;
  final String symbol;
  final TradeSide side;
  final OrderType type; // limit or stopLoss, never market
  final int quantity; // units of 1/10,000 share
  final int triggerPriceCents; // limit price, or stop price
  final DateTime createdAt;

  /// Cash a limit buy holds back: its cost at the limit price. It fills at
  /// or below the limit, so the real cost never exceeds this.
  int get reservedCashCents =>
      side == TradeSide.buy ? costCents(quantity, triggerPriceCents) : 0;

  /// Limit buy: price ≤ limit. Limit sell: price ≥ limit.
  /// Stop-loss sell: price ≤ stop.
  bool triggersAt(int priceCents) => switch ((side, type)) {
    (TradeSide.buy, OrderType.limit) => priceCents <= triggerPriceCents,
    (TradeSide.sell, OrderType.limit) => priceCents >= triggerPriceCents,
    (TradeSide.sell, OrderType.stopLoss) => priceCents <= triggerPriceCents,
    _ => false,
  };
}
