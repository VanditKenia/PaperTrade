import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

import '../domain/models/holding.dart';
import '../domain/models/pending_order.dart';
import '../domain/models/portfolio_state.dart';
import '../domain/models/trade.dart';
import '../domain/models/wallet.dart';
import '../domain/portfolio_engine.dart';
import '../domain/quantity.dart';
import 'local_store.dart';
import 'storage_error.dart';

final portfolioRepositoryProvider = Provider<PortfolioRepository>(
  (ref) => PortfolioRepository(ref.watch(localStoreProvider)),
);

/// Loads and saves the whole [PortfolioState] as plain maps in Hive.
class PortfolioRepository {
  PortfolioRepository(this._store);

  final LocalStore _store;

  /// False on first launch: the app then asks for a starting balance.
  bool get hasSaved => _cash(_store.readPortfolio()) != null;

  /// Nothing saved yet loads the default wallet (onboarding replaces it).
  PortfolioState load() {
    final raw = _store.readPortfolio();
    final cash = _cash(raw);
    if (raw is! Map || cash == null) return PortfolioState.initial();

    // Migration: data saved before custom balances has no 'start'; those
    // accounts all began with the default. A corrupt value falls back too,
    // which also rules out dividing by zero in the total return %.
    final start = _int(raw['start']);
    // Migration: before fractional shares (no 'v') quantities were whole
    // shares and holdings stored an avg per share instead of a cost basis.
    final legacy = _int(raw['v']) != _version;

    final holdings = [
      for (final h in _list(raw['holdings'])) ?_holding(h, legacy),
    ];
    final trades = [for (final t in _list(raw['trades'])) ?_trade(t, legacy)];
    // Data from before limit orders simply has no 'orders' key: none open.
    final orders = [for (final o in _list(raw['orders'])) ?_order(o)];
    return PortfolioState(
      wallet: Wallet(cashCents: cash),
      startingCashCents:
          start != null && PortfolioEngine.isValidStartingCash(start)
          ? start
          : defaultStartingCashCents,
      holdings: {for (final h in holdings) h.symbol: h},
      trades: trades,
      orders: orders,
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
    'v': _version,
    'cash': state.wallet.cashCents,
    'start': state.startingCashCents,
    'holdings': [
      for (final h in state.holdings.values)
        {'symbol': h.symbol, 'qty': h.quantity, 'basis': h.costBasisCents},
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
          'type': t.orderType.name,
        },
    ],
    'orders': [
      for (final o in state.orders)
        {
          'id': o.id,
          'symbol': o.symbol,
          'side': o.side.name,
          'type': o.type.name,
          'qty': o.quantity,
          'price': o.triggerPriceCents,
          'at': o.createdAt.millisecondsSinceEpoch,
        },
    ],
  });

  static Holding? _holding(Object? h, bool legacy) {
    if (h is! Map || h['symbol'] is! String) return null;
    final qty = _int(h['qty']);
    if (qty == null || qty < 1) return null;
    final int? basis;
    if (legacy) {
      final avg = _int(h['avg']);
      basis = avg == null || avg < 1 ? null : qty * avg;
    } else {
      basis = _int(h['basis']);
    }
    if (basis == null || basis < 0) return null;
    return Holding(
      symbol: h['symbol'] as String,
      quantity: legacy ? qty * unitsPerShare : qty,
      costBasisCents: basis,
    );
  }

  static Trade? _trade(Object? t, bool legacy) {
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
      quantity: legacy ? qty * unitsPerShare : qty,
      priceCents: price,
      executedAt: DateTime.fromMillisecondsSinceEpoch(at),
      realizedPnlCents: _int(t['pnl']),
      // Trades from before limit orders have no 'type': they were market.
      orderType: _orderTypes[t['type']] ?? OrderType.market,
    );
  }

  /// Skips anything that isn't a valid open order, so corrupt data can't
  /// reserve cash or shares (or reach the matcher).
  static PendingOrder? _order(Object? o) {
    if (o is! Map || o['id'] is! String || o['symbol'] is! String) return null;
    final side = TradeSide.values.asNameMap()[o['side']];
    final type = _orderTypes[o['type']];
    final qty = _int(o['qty']);
    final price = _int(o['price']);
    final at = _int(o['at']);
    if (side == null ||
        type == null ||
        type == OrderType.market ||
        (type == OrderType.stopLoss && side == TradeSide.buy) ||
        qty == null ||
        qty < 1 ||
        price == null ||
        price < 1 ||
        at == null) {
      return null;
    }
    return PendingOrder(
      id: o['id'] as String,
      symbol: o['symbol'] as String,
      side: side,
      type: type,
      quantity: qty,
      triggerPriceCents: price,
      createdAt: DateTime.fromMillisecondsSinceEpoch(at),
    );
  }

  static final _orderTypes = OrderType.values.asNameMap();

  // Bumped when the saved shape changes; 2 = fractional quantity units.
  static const _version = 2;

  static int? _cash(Object? raw) => raw is Map ? _int(raw['cash']) : null;

  static List<Object?> _list(Object? v) => v is List ? v : const [];

  /// On web, Hive (IndexedDB) has no separate int type and can hand back a
  /// whole-number double, so accept those but never a fractional value.
  static int? _int(Object? v) => switch (v) {
    int() => v,
    double() when v.isFinite && v == v.truncateToDouble() => v.toInt(),
    _ => null,
  };
}
