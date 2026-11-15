import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/history_repository.dart';
import '../../data/price_stream_service.dart';
import '../../domain/models/chart_range.dart';
import '../../domain/models/price_point.dart';
import '../watchlist/watchlist_provider.dart';

typedef HistoryKey = ({String symbol, ChartRange range});

/// Chart history for one symbol and range. Reads only the history
/// repository: like every price provider, it must never depend on the
/// portfolio.
final historyProvider = AsyncNotifierProvider.autoDispose
    .family<HistoryNotifier, List<PricePoint>, HistoryKey>(
      HistoryNotifier.new,
      // Every retry spends one of 8 requests/min; let the user decide.
      retry: (_, _) => null,
    );

class HistoryNotifier extends AsyncNotifier<List<PricePoint>> {
  HistoryNotifier(this.key);

  final HistoryKey key;

  @override
  Future<List<PricePoint>> build() =>
      ref.watch(historyRepositoryProvider).history(key.symbol, key.range);

  /// Retry button. Fresh cached data answers without a request.
  void reload() => ref.invalidateSelf();
}

/// Live ticks for one symbol, collected only while its detail screen is
/// open. autoDispose throws them away on close.
final liveTicksProvider = NotifierProvider.autoDispose
    .family<LiveTicksNotifier, List<PricePoint>, String>(LiveTicksNotifier.new);

class LiveTicksNotifier extends Notifier<List<PricePoint>> {
  LiveTicksNotifier(this.symbol);

  final String symbol;

  // shortcut: keeps the last 300 ticks, roughly 2.5 min of busy ticks at
  // 2/s; downsample into 5-min bars if longer sessions matter.
  static const maxPoints = 300;

  @override
  List<PricePoint> build() {
    // Subscribe even if the symbol isn't on the watchlist (opened from
    // search), and drop that subscription when the screen closes.
    final service = ref.read(priceStreamServiceProvider);
    final source = 'detail:$symbol';
    service.setSymbols([symbol], source: source);
    ref.onDispose(() => service.setSymbols(const [], source: source));

    // select() fires only when this symbol's price changes, so each point
    // is a real move, not a repeat of a snapshot caused by another symbol.
    final sub = ref.listen(livePricesProvider.select((p) => p.value?[symbol]), (
      _,
      price,
    ) {
      if (price != null) _add(price);
    });
    final live = sub.read();
    return [if (live != null) _point(live)];
  }

  // The socket only gives us the latest price, so the tick is stamped on
  // arrival; with 500 ms throttling that's close enough for a chart.
  static PricePoint _point(int price) =>
      PricePoint(time: DateTime.now(), priceCents: price);

  void _add(int price) {
    final next = [...state, _point(price)];
    state = next.length > maxPoints
        ? next.sublist(next.length - maxPoints)
        : next;
  }
}

/// What the chart draws: history, plus on 1D the live ticks newer than the
/// last bar, so the line keeps moving between 5-minute bars.
List<PricePoint> chartPoints(
  ChartRange range,
  List<PricePoint> history,
  List<PricePoint> ticks,
) {
  if (range != ChartRange.day) return history;
  final after = history.isEmpty ? null : history.last.time;
  return [
    ...history,
    for (final t in ticks)
      if (after == null || t.time.isAfter(after)) t,
  ];
}
