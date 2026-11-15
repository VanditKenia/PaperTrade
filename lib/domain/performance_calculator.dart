import 'models/trade.dart';
import 'quantity.dart';

/// Trading results computed from the trade list. Only sells have a
/// realized P&L, so win/loss numbers are about sells.
class PerformanceStats {
  const PerformanceStats({
    required this.totalRealizedPnlCents,
    required this.tradeCount,
    required this.sellCount,
    required this.winCount,
    required this.winRate,
    required this.averageWinCents,
    required this.averageLossCents,
    required this.bestTrade,
    required this.worstTrade,
  });

  final int totalRealizedPnlCents; // Σ realized P&L of sells
  final int tradeCount; // buys + sells
  final int sellCount;
  final int winCount; // sells with realized P&L > 0
  final double? winRate; // winCount / sellCount × 100; null without sells
  final int? averageWinCents; // null without wins
  final int? averageLossCents; // negative; null without losses
  final Trade? bestTrade; // sell with the highest realized P&L
  final Trade? worstTrade; // sell with the lowest realized P&L
}

/// Pure: same trades in, same numbers out.
abstract final class PerformanceCalculator {
  static PerformanceStats calculate(List<Trade> trades) {
    final sells = [
      for (final t in trades)
        if (t.realizedPnlCents != null) t,
    ];
    final wins = [
      for (final t in sells)
        if (t.realizedPnlCents! > 0) t.realizedPnlCents!,
    ];
    // A break-even sell (P&L 0) counts toward the win rate's sells but is
    // neither a win nor a loss.
    final losses = [
      for (final t in sells)
        if (t.realizedPnlCents! < 0) t.realizedPnlCents!,
    ];

    Trade? best;
    Trade? worst;
    // Strict comparisons keep the earliest trade on ties.
    for (final t in sells) {
      if (best == null || t.realizedPnlCents! > best.realizedPnlCents!) {
        best = t;
      }
      if (worst == null || t.realizedPnlCents! < worst.realizedPnlCents!) {
        worst = t;
      }
    }

    return PerformanceStats(
      totalRealizedPnlCents: sells.fold(
        0,
        (sum, t) => sum + t.realizedPnlCents!,
      ),
      tradeCount: trades.length,
      sellCount: sells.length,
      winCount: wins.length,
      winRate: sells.isEmpty ? null : wins.length / sells.length * 100,
      averageWinCents: _average(wins),
      // Average the loss sizes, then negate: rounds -2.5¢ to -3¢, the same
      // way a 2.5¢ average win rounds to 3¢.
      averageLossCents: losses.isEmpty
          ? null
          : -_average([for (final l in losses) -l])!,
      bestTrade: best,
      worstTrade: worst,
    );
  }

  /// Mean in int cents, rounded half up (for non-negative values).
  static int? _average(List<int> cents) => cents.isEmpty
      ? null
      : mulDivHalfUp(cents.fold(0, (a, b) => a + b), 1, cents.length);
}
