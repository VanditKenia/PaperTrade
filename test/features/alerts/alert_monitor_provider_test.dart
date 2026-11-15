import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertrade/data/alert_repository.dart';
import 'package:papertrade/data/notification_service.dart';
import 'package:papertrade/domain/models/price_alert.dart';
import 'package:papertrade/features/alerts/alerts_provider.dart';
import 'package:papertrade/features/watchlist/watchlist_provider.dart';

import '../../fakes.dart';

void main() {
  late StreamController<Map<String, int>> prices;
  late FakeAlertRepository repo;
  late FakeNotificationService notifications;
  late ProviderContainer container;
  late List<PriceAlert?> pushed;

  setUp(() {
    repo = FakeAlertRepository();
    notifications = FakeNotificationService();
    prices = StreamController<Map<String, int>>();
    addTearDown(prices.close);
    container = ProviderContainer.test(
      overrides: [
        alertRepositoryProvider.overrideWithValue(repo),
        notificationServiceProvider.overrideWithValue(notifications),
        livePricesProvider.overrideWith((_) => prices.stream),
      ],
    );
    container.listen(alertMonitorProvider, (_, _) {});
    pushed = [];
    container.listen(lastTriggeredAlertProvider, (_, a) => pushed.add(a));
  });

  Future<void> tick(Map<String, int> snapshot) async {
    prices.add(snapshot);
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> addAlert(AlertDirection direction, int target) => container
      .read(alertsProvider.notifier)
      .add(symbol: 'AAPL', direction: direction, targetCents: target);

  List<PriceAlert> alerts() => container.read(alertsProvider);

  test('fires on crossing: marks triggered, persists, notifies', () async {
    await addAlert(AlertDirection.above, 20000);
    await tick({'AAPL': 19900});
    expect(alerts().single.isTriggered, isFalse);

    await tick({'AAPL': 20015});
    final a = alerts().single;
    expect(a.isTriggered, isTrue);
    expect(a.triggeredPriceCents, 20015);
    expect(repo.saved.single.isTriggered, isTrue);
    expect(notifications.shown, [r'AAPL rose above $200.00 · now $200.15']);
    expect(pushed.single!.id, a.id);
  });

  test('fires once even if the price crosses again', () async {
    await addAlert(AlertDirection.below, 18000);
    await tick({'AAPL': 18100});
    await tick({'AAPL': 17900}); // fires
    await tick({'AAPL': 18200});
    await tick({'AAPL': 17800}); // crosses again: no second fire
    expect(notifications.shown, hasLength(1));
    expect(pushed, hasLength(1));
    expect(alerts().single.triggeredPriceCents, 17900);
  });

  test('no fire while the price stays on the far side', () async {
    await tick({'AAPL': 20500});
    await addAlert(AlertDirection.above, 20000); // already above
    await tick({'AAPL': 20600});
    expect(alerts().single.isTriggered, isFalse);
  });

  test('a deleted alert never fires', () async {
    await addAlert(AlertDirection.above, 20000);
    await container.read(alertsProvider.notifier).delete(alerts().single.id);
    await tick({'AAPL': 19000});
    await tick({'AAPL': 21000});
    expect(notifications.shown, isEmpty);
    expect(repo.saved, isEmpty);
  });

  test('a failed save still marks it triggered (no double fire)', () async {
    await addAlert(AlertDirection.above, 20000);
    repo.failSaves = true;
    await tick({'AAPL': 19000});
    await tick({'AAPL': 21000});
    await tick({'AAPL': 19000});
    await tick({'AAPL': 21000});
    expect(alerts().single.isTriggered, isTrue);
    expect(notifications.shown, hasLength(1));
  });
}
