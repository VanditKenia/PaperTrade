import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/price_stream_service.dart';
import '../../domain/models/quote.dart';
import '../watchlist/watchlist_provider.dart';

/// Chart prices for one symbol, collected only while its detail screen is
/// open. autoDispose throws the points away on close.
final chartPointsProvider = NotifierProvider.autoDispose
    .family<ChartPointsNotifier, ChartPoints, String>(ChartPointsNotifier.new);

/// Seed points from the quote plus live ticks (cents, oldest first).
class ChartPoints {
  const ChartPoints({this.seed = const [], this.live = const []});

  /// Live ticks needed before the seed points are dropped.
  static const liveOnlyAfter = 10;

  final List<int> seed;
  final List<int> live;

  /// The seed spans the whole day (prev close → now), which squashes small
  /// live moves into a flat line. Once there are enough ticks to draw a
  /// real shape, show only those so the y-axis zooms in on them.
  List<int> get visible =>
      live.length >= liveOnlyAfter ? live : [...seed, ...live];
}

class ChartPointsNotifier extends Notifier<ChartPoints> {
  ChartPointsNotifier(this.symbol);

  final String symbol;

  // shortcut: keeps the last 300 points, roughly 2.5 min of busy ticks at
  // 2/s; store timestamps and downsample if longer sessions matter.
  static const maxPoints = 300;

  @override
  ChartPoints build() {
    // Subscribe even if the symbol isn't on the watchlist (opened from
    // search), and drop that subscription when the screen closes.
    final service = ref.read(priceStreamServiceProvider);
    final source = 'detail:$symbol';
    service.setSymbols([symbol], source: source);
    ref.onDispose(() => service.setSymbols(const [], source: source));

    // Listeners handle later changes only. Values that already exist (e.g.
    // the watchlist loaded the quote) are read below and returned as the
    // initial state: `state` can't be touched until build() returns.
    var seeded = false;
    final quoteSub = ref.listen(quoteProvider(symbol), (_, quote) {
      final q = quote.value;
      if (seeded || q == null) return;
      seeded = true;
      state = ChartPoints(seed: _seed(q), live: state.live);
    });

    // select() fires only when this symbol's price changes, so each point
    // is a real move, not a repeat of a snapshot caused by another symbol.
    final liveSub = ref.listen(
      livePricesProvider.select((p) => p.value?[symbol]),
      (_, price) {
        if (price != null) _add(price);
      },
    );

    final quote = quoteSub.read().value;
    final live = liveSub.read();
    seeded = quote != null;
    return ChartPoints(
      seed: quote == null ? const [] : _seed(quote),
      live: [?live],
    );
  }

  /// Previous close → open → latest quote: a rough shape of the day so far,
  /// so the chart is never empty even before any tick (or market closed).
  static List<int> _seed(Quote q) => [
    for (final p in [q.prevCloseCents, q.openCents, q.currentCents])
      if (p > 0) p,
  ];

  void _add(int price) {
    final next = [...state.live, price];
    state = ChartPoints(
      seed: state.seed,
      live: next.length > maxPoints
          ? next.sublist(next.length - maxPoints)
          : next,
    );
  }
}
