import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/trade.dart';
import '../portfolio/portfolio_provider.dart';

/// One calendar day of trades (local time), newest trade first.
typedef TradeDay = ({DateTime day, List<Trade> trades});

/// Trades grouped by day, newest day first (UI_UX.md §3.6).
final tradeHistoryProvider = Provider<List<TradeDay>>(
  (ref) => groupByDay(ref.watch(portfolioProvider.select((p) => p.trades))),
);

/// [trades] are stored oldest first, so walking them backwards gives newest
/// first, and each day's trades end up next to each other.
List<TradeDay> groupByDay(List<Trade> trades) {
  final days = <TradeDay>[];
  for (final trade in trades.reversed) {
    final t = trade.executedAt.toLocal();
    final day = DateTime(t.year, t.month, t.day);
    if (days.isEmpty || days.last.day != day) {
      days.add((day: day, trades: []));
    }
    days.last.trades.add(trade);
  }
  return days;
}
