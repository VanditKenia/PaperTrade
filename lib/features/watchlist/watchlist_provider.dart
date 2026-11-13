import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local_store.dart';
import '../../data/market_repository.dart';
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

final quoteProvider = FutureProvider.family<Quote, String>(
  (ref, symbol) => ref.watch(marketRepositoryProvider).quote(symbol),
  // Riverpod retries failures by default; for a 401 or 429 that would just
  // spam the API. The user retries with pull-to-refresh instead.
  retry: (_, _) => null,
);
