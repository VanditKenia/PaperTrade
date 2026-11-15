import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

import '../domain/value_history.dart';
import 'local_store.dart';
import 'storage_error.dart';

final valueHistoryRepositoryProvider = Provider<ValueHistoryRepository>(
  (ref) => ValueHistoryRepository(ref.watch(localStoreProvider)),
);

/// Saves value snapshots as compact `[millis, cents]` pairs.
class ValueHistoryRepository {
  ValueHistoryRepository(this._store);

  final LocalStore _store;

  /// Bad entries are skipped; nothing saved yet loads as empty.
  List<ValueSnapshot> load() {
    final raw = _store.readValueHistory();
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is List && item.length == 2)
          if ((_int(item[0]), _int(item[1])) case (final t?, final v?))
            ValueSnapshot(
              time: DateTime.fromMillisecondsSinceEpoch(t),
              valueCents: v,
            ),
    ];
  }

  /// Throws [StorageError] if the write fails.
  Future<void> save(List<ValueSnapshot> history) async {
    try {
      await _store.writeValueHistory([
        for (final s in history) [s.time.millisecondsSinceEpoch, s.valueCents],
      ]);
    } on HiveError catch (e) {
      throw StorageError(e);
    } on Exception catch (e) {
      throw StorageError(e);
    }
  }

  // Same rule as PortfolioRepository: web storage may return whole-number
  // doubles for ints; never accept a fraction.
  static int? _int(Object? v) => switch (v) {
    int() => v,
    double() when v.isFinite && v == v.truncateToDouble() => v.toInt(),
    _ => null,
  };
}
