import 'models/price_alert.dart';

/// Pure trigger rules for price alerts. The provider that feeds them live
/// prices is features/alerts/alert_monitor_provider.dart.
abstract final class AlertRules {
  /// True when the move from [previous] to [current] crosses the target:
  /// "above" fires going from below the target to at/above it, "below" the
  /// other way. A price that was already past the target doesn't fire
  /// again until it comes back and crosses anew.
  ///
  /// [previous] is null for the first price seen since the app opened;
  /// then a price already past the target fires, since it crossed while
  /// the app was closed (or the alert was created on the far side).
  static bool crosses(PriceAlert alert, int? previous, int current) {
    final target = alert.targetCents;
    return switch (alert.direction) {
      AlertDirection.above =>
        current >= target && (previous == null || previous < target),
      AlertDirection.below =>
        current <= target && (previous == null || previous > target),
    };
  }

  /// Waiting alerts that fire on the step from [previous] to [next]
  /// snapshot, with the price that fired each. Triggered alerts never fire
  /// again (fire once), and only symbols whose price changed are checked.
  static List<(PriceAlert, int)> triggered(
    List<PriceAlert> alerts,
    Map<String, int> previous,
    Map<String, int> next,
  ) => [
    for (final a in alerts)
      if (!a.isTriggered)
        if (next[a.symbol] case final price?
            when price != previous[a.symbol] &&
                crosses(a, previous[a.symbol], price))
          (a, price),
  ];

  /// UI check before creating: the target must still be ahead, otherwise
  /// the alert would fire on the next tick. Null = fine.
  static String? targetError(
    AlertDirection direction,
    int? targetCents,
    int? currentCents,
  ) {
    if (targetCents == null || targetCents < 1) return 'Enter a price';
    if (currentCents == null) return null;
    if (direction == AlertDirection.above && targetCents <= currentCents) {
      return 'Must be above the current price';
    }
    if (direction == AlertDirection.below && targetCents >= currentCents) {
      return 'Must be below the current price';
    }
    return null;
  }
}
