import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../domain/models/stock.dart';

/// Overridden in main() with a store whose box is already open, so providers
/// can read it synchronously.
final localStoreProvider = Provider<LocalStore>(
  (ref) => throw UnimplementedError('localStoreProvider not overridden'),
);

/// First-launch watchlist (APP_FLOW.md §2). BTC trades 24/7, so live ticks
/// can be tested while the US market is closed.
const defaultWatchlist = [
  Stock(symbol: 'AAPL', name: 'Apple Inc'),
  Stock(symbol: 'MSFT', name: 'Microsoft Corp'),
  Stock(symbol: 'GOOGL', name: 'Alphabet Inc'),
  Stock(symbol: 'AMZN', name: 'Amazon.com Inc'),
  Stock(symbol: 'TSLA', name: 'Tesla Inc'),
  Stock(symbol: 'BINANCE:BTCUSDT', name: 'Bitcoin / Tether'),
];

/// Hive-backed storage. Stores plain maps/lists so no type adapters are needed.
class LocalStore {
  LocalStore(this._box);

  final Box<dynamic> _box;

  static const _watchlistKey = 'watchlist';
  static const _portfolioKey = 'portfolio';
  static const _introSeenKey = 'introSeen';
  static const _valueHistoryKey = 'valueHistory';
  static const _alertsKey = 'alerts';

  static Future<LocalStore> open() async {
    await Hive.initFlutter();
    return LocalStore(await Hive.openBox<dynamic>('papertrade'));
  }

  List<Stock> loadWatchlist() {
    final raw = _box.get(_watchlistKey);
    // No key yet = first launch. An empty list means the user cleared it,
    // so don't re-seed in that case.
    if (raw is! List) return defaultWatchlist;
    return [
      for (final item in raw)
        if (item is Map && item['symbol'] is String && item['name'] is String)
          Stock(symbol: item['symbol'] as String, name: item['name'] as String),
    ];
  }

  Future<void> saveWatchlist(List<Stock> stocks) => _box.put(_watchlistKey, [
    for (final s in stocks) {'symbol': s.symbol, 'name': s.name},
  ]);

  /// False until the user dismisses the first-launch banner.
  bool get introSeen => _box.get(_introSeenKey) == true;

  Future<void> markIntroSeen() => _box.put(_introSeenKey, true);

  /// The whole portfolio as one raw map, or null on first launch.
  Object? readPortfolio() => _box.get(_portfolioKey);

  /// One put = one write: cash, holdings and trades are saved together or
  /// not at all, so a crash can't leave cash debited without the holding.
  Future<void> writePortfolio(Map<String, Object?> data) =>
      _box.put(_portfolioKey, data);

  /// Portfolio value snapshots for Stats. Kept apart from the portfolio
  /// value so a trade save doesn't rewrite up to 2,000 snapshots.
  Object? readValueHistory() => _box.get(_valueHistoryKey);

  Future<void> writeValueHistory(List<Object?> data) =>
      _box.put(_valueHistoryKey, data);

  Object? readAlerts() => _box.get(_alertsKey);

  Future<void> writeAlerts(List<Object?> data) => _box.put(_alertsKey, data);
}
