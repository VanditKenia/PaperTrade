import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

import '../domain/models/holding.dart';
import '../domain/models/portfolio_state.dart';
import '../domain/models/trade.dart';
import '../domain/models/wallet.dart';
import 'local_store.dart';
import 'storage_error.dart';

final portfolioRepositoryProvider = Provider<PortfolioRepository>(
  (ref) => PortfolioRepository(ref.watch(localStoreProvider)),
);

/// Loads and saves the whole [PortfolioState] as plain maps in Hive.
class PortfolioRepository {
  PortfolioRepository(this._store);

  final LocalStore _store;

  /// First launch (nothing saved) starts with the $100,000 wallet.
  PortfolioState load() {
    final raw = _store.readPortfolio();
    final cash = raw is Map ? _int(raw['cash']) : null;
    if (raw is! Map || cash == null) return PortfolioState.initial();

    final holdings = [for (final h in _list(raw['holdings'])) ?_holding(h)];
    final trades = [for (final t in _list(raw['trades'])) ?_trade(t)];
    return PortfolioState(
      wallet: Wallet(cashCents: cash),
      holdings: {for (final h in holdings) h.symbol: h},
      trades: trades,
    );
  }

  // shortcut: rewrites every trade on each save; fine for hundreds of
  // trades, split trades into their own box if history gets large.
  /// Throws [StorageError] if the write fails. Only storage failures are
  /// wrapped: a programming error (an Error) still surfaces as itself.
  Future<void> save(PortfolioState state) async {
    try {
      await _write(state);
    } on HiveError catch (e) {
      throw StorageError(e);
    } on Exception catch (e) {
      // Disk full, IndexedDB quota, etc.
      throw StorageError(e);
    }
  }

  Future<void> _write(PortfolioState state) => _store.writePortfolio({
    'cash': state.wallet.cashCents,
    'holdings': [
      for (final h in state.holdings.values)
        {'symbol': h.symbol, 'qty': h.quantity, 'avg': h.avgCostCents},
    ],
    'trades': [
      for (final t in state.trades)
        {
          'id': t.id,
          'symbol': t.symbol,
          'side': t.side.name,
          'qty': t.quantity,
          'price': t.priceCents,
          'at': t.executedAt.millisecondsSinceEpoch,
          'pnl': t.realizedPnlCents,
        },
    ],
  });

  static Holding? _holding(Object? h) {
    if (h is! Map || h['symbol'] is! String) return null;
    final qty = _int(h['qty']);
    final avg = _int(h['avg']);
    if (qty == null || qty < 1 || avg == null || avg < 1) return null;
    return Holding(
      symbol: h['symbol'] as String,
      quantity: qty,
      avgCostCents: avg,
    );
  }

  static Trade? _trade(Object? t) {
    if (t is! Map || t['id'] is! String || t['symbol'] is! String) return null;
    final side = TradeSide.values.asNameMap()[t['side']];
    final qty = _int(t['qty']);
    final price = _int(t['price']);
    final at = _int(t['at']);
    if (side == null || qty == null || price == null || at == null) {
      return null;
    }
    return Trade(
      id: t['id'] as String,
      symbol: t['symbol'] as String,
      side: side,
      quantity: qty,
      priceCents: price,
      executedAt: DateTime.fromMillisecondsSinceEpoch(at),
      realizedPnlCents: _int(t['pnl']),
    );
  }

  static List<Object?> _list(Object? v) => v is List ? v : const [];

  /// On web, Hive (IndexedDB) has no separate int type and can hand back a
  /// whole-number double, so accept those but never a fractional value.
  static int? _int(Object? v) => switch (v) {
    int() => v,
    double() when v.isFinite && v == v.truncateToDouble() => v.toInt(),
    _ => null,
  };
}
