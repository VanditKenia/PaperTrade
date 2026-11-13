import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/local_store.dart';
import '../../data/market_repository.dart';
import '../../data/price_stream_service.dart';
import '../../domain/models/quote.dart';
import '../../domain/models/stock.dart';

final watchlistProvider = NotifierProvider<WatchlistNotifier, List<Stock>>(
  WatchlistNotifier.new,
);

/// The user's watched stocks, persisted to Hive on every change.
class WatchlistNotifier extends Notifier<List<Stock>> {
  @override
  List<Stock> build() => ref.watch(localStoreProvider).loadWatchlist();

  void add(Stock stock) {
    if (state.any((s) => s.symbol == stock.symbol)) return;
    _save([...state, stock]);
  }

  void remove(String symbol) => _save([
    for (final s in state)
      if (s.symbol != symbol) s,
  ]);

  void _save(List<Stock> stocks) {
    state = stocks;
    // Hive updates its in-memory copy immediately; the disk write can finish
    // in the background.
    unawaited(ref.read(localStoreProvider).saveWatchlist(stocks));
  }
}

/// Latest live price (cents) per symbol, updated at most every 500 ms.
final livePricesProvider = StreamProvider<Map<String, int>>((ref) {
  final service = ref.watch(priceStreamServiceProvider);

  ref.listen(
    watchlistProvider,
    (_, stocks) => service.setSymbols(stocks.map((s) => s.symbol)),
    fireImmediately: true,
  );

  // A socket left open in the background wastes battery and the OS may kill
  // it anyway; reconnect cleanly when the user comes back.
  final lifecycle = AppLifecycleListener(
    onPause: service.stop,
    onResume: service.start,
  );
  ref.onDispose(lifecycle.dispose);

  service.start();
  return service.prices;
});

final quoteProvider = FutureProvider.family<Quote, String>(
  (ref, symbol) => ref.watch(marketRepositoryProvider).quote(symbol),
  // Riverpod retries failures by default; for a 401 or 429 that would just
  // spam the API. The user retries with pull-to-refresh instead.
  retry: (_, _) => null,
);
