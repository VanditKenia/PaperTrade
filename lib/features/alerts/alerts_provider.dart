import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../data/alert_repository.dart';
import '../../data/notification_service.dart';
import '../../domain/alert_rules.dart';
import '../../domain/models/price_alert.dart';
import '../watchlist/watchlist_provider.dart';

final alertsProvider = NotifierProvider<AlertsNotifier, List<PriceAlert>>(
  AlertsNotifier.new,
);

/// All price alerts, oldest first. Reads only its repository: never prices.
class AlertsNotifier extends Notifier<List<PriceAlert>> {
  @override
  List<PriceAlert> build() => ref.watch(alertRepositoryProvider).load();

  /// Throws StorageError if the save fails; state is then unchanged.
  Future<PriceAlert> add({
    required String symbol,
    required AlertDirection direction,
    required int targetCents,
  }) async {
    final now = DateTime.now();
    final alert = PriceAlert(
      id: 'a${now.microsecondsSinceEpoch}-${state.length}',
      symbol: symbol,
      direction: direction,
      targetCents: targetCents,
      createdAt: now,
    );
    await _save([...state, alert]);
    return alert;
  }

  /// Throws StorageError if the save fails; state is then unchanged.
  Future<void> delete(String id) => _save([
    for (final a in state)
      if (a.id != id) a,
  ]);

  /// Marks it fired. State changes before the save so a slow or failed
  /// write can never make the same alert fire twice.
  Future<void> markTriggered(String id, int priceCents, DateTime at) async {
    state = [
      for (final a in state) a.id == id ? a.triggered(priceCents, at) : a,
    ];
    try {
      await ref.read(alertRepositoryProvider).save(state);
    } on Exception catch (e) {
      if (kDebugMode) debugPrint('Saving triggered alert failed: $e');
    }
  }

  Future<void> _save(List<PriceAlert> next) async {
    await ref.read(alertRepositoryProvider).save(next);
    state = next;
  }
}

/// The most recently fired alert. AppShell listens and shows a snackbar,
/// so the monitor never needs a BuildContext.
final lastTriggeredAlertProvider =
    NotifierProvider<LastTriggeredAlertNotifier, PriceAlert?>(
      LastTriggeredAlertNotifier.new,
    );

class LastTriggeredAlertNotifier extends Notifier<PriceAlert?> {
  @override
  PriceAlert? build() => null;

  void push(PriceAlert alert) => state = alert;
}

/// Fires waiting alerts when a live tick crosses their target, once each.
///
/// Watches prices and reads alerts; nothing reads this back, so no cycle
/// (same pattern as orderMatcherProvider). Kept alive by AppShell, so
/// alerts only work while the app is open.
final alertMonitorProvider = Provider<void>((ref) {
  ref.listen(livePricesProvider, (previous, next) {
    final prices = next.value;
    if (prices == null) return;
    final alerts = ref.read(alertsProvider);
    final now = DateTime.now();
    for (final (alert, price) in AlertRules.triggered(
      alerts,
      previous?.value ?? const {},
      prices,
    )) {
      final fired = alert.triggered(price, now);
      unawaited(
        ref.read(alertsProvider.notifier).markTriggered(alert.id, price, now),
      );
      ref.read(lastTriggeredAlertProvider.notifier).push(fired);
      unawaited(
        ref
            .read(notificationServiceProvider)
            // Notification ids are ints; the string id's hash is stable
            // enough for one notification per alert.
            .show(
              alert.id.hashCode & 0x7fffffff,
              'Price alert',
              alertMessage(fired),
            ),
      );
    }
  });
});

/// "AAPL rose above $200.00 · now $200.15".
String alertMessage(PriceAlert a) {
  final verb = a.direction == AlertDirection.above
      ? 'rose above'
      : 'fell below';
  final now = a.triggeredPriceCents;
  return '${a.symbol} $verb ${formatCents(a.targetCents)}'
      '${now == null ? '' : ' · now ${formatCents(now)}'}';
}

/// "Rises above $200.00" / "Falls below $180.00".
String alertCondition(PriceAlert a) =>
    '${a.direction == AlertDirection.above ? 'Rises above' : 'Falls below'} '
    '${formatCents(a.targetCents)}';
