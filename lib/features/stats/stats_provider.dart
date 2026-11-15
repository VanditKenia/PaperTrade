import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/value_history_repository.dart';
import '../../domain/performance_calculator.dart';
import '../../domain/value_history.dart';
import '../portfolio/portfolio_provider.dart';

/// Win rate, averages, best/worst from the trade list.
final performanceStatsProvider = Provider<PerformanceStats>(
  (ref) => PerformanceCalculator.calculate(
    ref.watch(portfolioProvider.select((p) => p.trades)),
  ),
);

final valueHistoryProvider =
    NotifierProvider<ValueHistoryNotifier, List<ValueSnapshot>>(
      ValueHistoryNotifier.new,
    );

/// Portfolio value snapshots, oldest first. Reads only its repository, so
/// it never depends on prices or the portfolio.
class ValueHistoryNotifier extends Notifier<List<ValueSnapshot>> {
  ValueHistoryNotifier({DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final DateTime Function() _now; // injectable for tests

  @override
  List<ValueSnapshot> build() =>
      ref.watch(valueHistoryRepositoryProvider).load();

  /// Adds a snapshot. Timed ones ([force] false) are skipped until
  /// [ValueHistory.interval] has passed since the last snapshot.
  Future<void> record(int valueCents, {bool force = false}) {
    final at = _now();
    if (!force && !ValueHistory.isDue(state, at)) return Future.value();
    state = ValueHistory.append(
      state,
      ValueSnapshot(time: at, valueCents: valueCents),
    );
    return _save();
  }

  /// After an account reset the old curve no longer applies.
  Future<void> clear() {
    state = const [];
    return _save();
  }

  // Shown even if saving fails: a lost snapshot is harmless, unlike a lost
  // trade, so it isn't worth bothering the user.
  Future<void> _save() async {
    try {
      await ref.read(valueHistoryRepositoryProvider).save(state);
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('Saving value history failed: $e');
    }
  }
}

/// Records the portfolio value on every trade and about every 5 minutes
/// while the app is open; clears the history when the account is reset.
///
/// Reads the price-based summary and watches the portfolio; nothing reads
/// this back, so no cycle (same pattern as orderMatcherProvider). Kept
/// alive by AppShell.
final snapshotRecorderProvider = Provider<void>((ref) {
  final history = ref.read(valueHistoryProvider.notifier);
  int value() => ref.read(portfolioSummaryProvider).portfolioValueCents;

  ref.listen(portfolioProvider, (previous, next) {
    if (previous == null) return;
    // Reset: trades disappear or the starting balance changes.
    final reset =
        next.trades.length < previous.trades.length ||
        next.startingCashCents != previous.startingCashCents;
    if (reset) unawaited(history.clear());
    if (reset || next.trades.length > previous.trades.length) {
      // Deferred so the summary has recomputed from the new state; read
      // inside this listener it can still hold the value before the trade.
      scheduleMicrotask(() {
        if (ref.mounted) unawaited(history.record(value(), force: true));
      });
    }
  });

  // On open (if due). Deferred: a provider may not change another one
  // while it is still building.
  scheduleMicrotask(() {
    if (ref.mounted) unawaited(history.record(value()));
  });
  // Checks every minute but records only when 5 minutes have passed since
  // the last snapshot, so a trade snapshot also resets the 5-minute clock.
  final timer = Timer.periodic(
    const Duration(minutes: 1),
    (_) => unawaited(history.record(value())),
  );
  ref.onDispose(timer.cancel);
});
