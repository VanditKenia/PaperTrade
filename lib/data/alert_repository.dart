import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

import '../domain/models/price_alert.dart';
import 'local_store.dart';
import 'storage_error.dart';

final alertRepositoryProvider = Provider<AlertRepository>(
  (ref) => AlertRepository(ref.watch(localStoreProvider)),
);

/// Saves price alerts as plain maps under their own Hive key.
class AlertRepository {
  AlertRepository(this._store);

  final LocalStore _store;

  /// Invalid entries are skipped; nothing saved yet loads as empty.
  List<PriceAlert> load() {
    final raw = _store.readAlerts();
    if (raw is! List) return const [];
    return [for (final a in raw) ?_alert(a)];
  }

  /// Throws [StorageError] if the write fails.
  Future<void> save(List<PriceAlert> alerts) async {
    try {
      await _store.writeAlerts([
        for (final a in alerts)
          {
            'id': a.id,
            'symbol': a.symbol,
            'dir': a.direction.name,
            'target': a.targetCents,
            'at': a.createdAt.millisecondsSinceEpoch,
            'firedAt': a.triggeredAt?.millisecondsSinceEpoch,
            'firedPrice': a.triggeredPriceCents,
          },
      ]);
    } on HiveError catch (e) {
      throw StorageError(e);
    } on Exception catch (e) {
      throw StorageError(e);
    }
  }

  static PriceAlert? _alert(Object? a) {
    if (a is! Map || a['id'] is! String || a['symbol'] is! String) return null;
    final direction = AlertDirection.values.asNameMap()[a['dir']];
    final target = _int(a['target']);
    final at = _int(a['at']);
    if (direction == null || target == null || target < 1 || at == null) {
      return null;
    }
    final firedAt = _int(a['firedAt']);
    return PriceAlert(
      id: a['id'] as String,
      symbol: a['symbol'] as String,
      direction: direction,
      targetCents: target,
      createdAt: DateTime.fromMillisecondsSinceEpoch(at),
      triggeredAt: firedAt == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(firedAt),
      triggeredPriceCents: _int(a['firedPrice']),
    );
  }

  // Same rule as PortfolioRepository: web storage may return whole-number
  // doubles for ints; never accept a fraction.
  static int? _int(Object? v) => switch (v) {
    int() => v,
    double() when v.isFinite && v == v.truncateToDouble() => v.toInt(),
    _ => null,
  };
}
