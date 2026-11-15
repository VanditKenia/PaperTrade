import 'package:flutter_test/flutter_test.dart';
import 'package:papertrade/domain/alert_rules.dart';
import 'package:papertrade/domain/models/price_alert.dart';

PriceAlert alert(
  AlertDirection direction,
  int target, {
  String id = 'a1',
  String symbol = 'AAPL',
  bool triggered = false,
}) {
  final a = PriceAlert(
    id: id,
    symbol: symbol,
    direction: direction,
    targetCents: target,
    createdAt: DateTime(2026, 11, 15),
  );
  return triggered ? a.triggered(target, DateTime(2026, 11, 15, 1)) : a;
}

void main() {
  group('crosses: above', () {
    final a = alert(AlertDirection.above, 20000);

    test('fires when the price moves from below to at/above the target', () {
      expect(AlertRules.crosses(a, 19999, 20000), isTrue);
      expect(AlertRules.crosses(a, 19000, 20500), isTrue);
    });

    test('does not fire below the target', () {
      expect(AlertRules.crosses(a, 19000, 19999), isFalse);
    });

    test('does not fire when it was already above (no crossing)', () {
      expect(AlertRules.crosses(a, 20000, 20100), isFalse);
      expect(AlertRules.crosses(a, 20500, 20100), isFalse);
    });

    test('first price since opening: fires if already past the target', () {
      expect(AlertRules.crosses(a, null, 20000), isTrue);
      expect(AlertRules.crosses(a, null, 19999), isFalse);
    });
  });

  group('crosses: below', () {
    final a = alert(AlertDirection.below, 18000);

    test('fires when the price moves from above to at/below the target', () {
      expect(AlertRules.crosses(a, 18001, 18000), isTrue);
      expect(AlertRules.crosses(a, 19000, 17000), isTrue);
    });

    test('does not fire above the target or when already below', () {
      expect(AlertRules.crosses(a, 19000, 18001), isFalse);
      expect(AlertRules.crosses(a, 18000, 17900), isFalse);
    });

    test('first price since opening: fires if already past the target', () {
      expect(AlertRules.crosses(a, null, 17999), isTrue);
      expect(AlertRules.crosses(a, null, 18001), isFalse);
    });
  });

  group('triggered', () {
    test('returns crossing alerts with the price that fired them', () {
      final up = alert(AlertDirection.above, 20000, id: 'up');
      final down = alert(AlertDirection.below, 18000, id: 'down');
      final hits = AlertRules.triggered([up, down], {'AAPL': 19900}, {
        'AAPL': 20050,
      });
      expect(hits.map((h) => h.$1.id), ['up']);
      expect(hits.single.$2, 20050);
    });

    test('fire once: a triggered alert never fires again', () {
      final done = alert(AlertDirection.above, 20000, triggered: true);
      expect(
        AlertRules.triggered([done], {'AAPL': 19000}, {'AAPL': 21000}),
        isEmpty,
      );
    });

    test('an unchanged price is not a tick', () {
      final a = alert(AlertDirection.above, 20000);
      expect(
        AlertRules.triggered([a], {'AAPL': 20000}, {'AAPL': 20000}),
        isEmpty,
      );
    });

    test('only the alert symbol counts', () {
      final a = alert(AlertDirection.above, 100, symbol: 'MSFT');
      expect(AlertRules.triggered([a], {}, {'AAPL': 99999}), isEmpty);
    });

    test('several alerts can fire on one tick', () {
      final a = alert(AlertDirection.above, 20000, id: 'x');
      final b = alert(AlertDirection.above, 20100, id: 'y');
      expect(
        AlertRules.triggered([a, b], {'AAPL': 19000}, {'AAPL': 20200}),
        hasLength(2),
      );
    });
  });

  group('targetError', () {
    test('needs a positive price', () {
      expect(
        AlertRules.targetError(AlertDirection.above, null, 100),
        'Enter a price',
      );
      expect(
        AlertRules.targetError(AlertDirection.above, 0, 100),
        'Enter a price',
      );
    });

    test('target must be ahead of the current price', () {
      expect(
        AlertRules.targetError(AlertDirection.above, 100, 100),
        'Must be above the current price',
      );
      expect(
        AlertRules.targetError(AlertDirection.below, 100, 100),
        'Must be below the current price',
      );
      expect(AlertRules.targetError(AlertDirection.above, 101, 100), isNull);
      expect(AlertRules.targetError(AlertDirection.below, 99, 100), isNull);
    });

    test('unknown current price: any positive target is fine', () {
      expect(AlertRules.targetError(AlertDirection.below, 5, null), isNull);
    });
  });
}
