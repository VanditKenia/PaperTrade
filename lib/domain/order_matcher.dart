import 'models/pending_order.dart';

/// Pure matching rules for open orders. The provider that feeds it live
/// prices lives in features/portfolio/order_matcher_provider.dart.
abstract final class OrderMatcher {
  /// Symbols whose price is new in [next] compared with [previous]: those
  /// are the ticks. An unchanged price isn't a new tick, so an order placed
  /// later never fills at a stale price.
  static Map<String, int> ticks(
    Map<String, int> previous,
    Map<String, int> next,
  ) => {
    for (final MapEntry(:key, :value) in next.entries)
      if (previous[key] != value) key: value,
  };

  /// Orders that [ticks] trigger, oldest first, each with the tick price
  /// it fills at. Every order has its own reservation, so all of them can
  /// fill on the same tick.
  static List<(PendingOrder, int)> triggered(
    List<PendingOrder> orders,
    Map<String, int> ticks,
  ) => [
    for (final o in orders)
      if (ticks[o.symbol] case final price? when o.triggersAt(price))
        (o, price),
  ];
}
