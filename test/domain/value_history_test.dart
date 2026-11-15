import 'package:flutter_test/flutter_test.dart';
import 'package:papertrade/domain/value_history.dart';

final t0 = DateTime(2026, 11, 15, 10);

ValueSnapshot at(Duration offset, [int value = 100]) =>
    ValueSnapshot(time: t0.add(offset), valueCents: value);

void main() {
  group('isDue', () {
    test('empty history is always due', () {
      expect(ValueHistory.isDue([], t0), isTrue);
    });

    test('due only once 5 minutes have passed since the last snapshot', () {
      final history = [at(Duration.zero)];
      expect(
        ValueHistory.isDue(history, t0.add(const Duration(minutes: 4))),
        isFalse,
      );
      expect(
        ValueHistory.isDue(history, t0.add(const Duration(minutes: 5))),
        isTrue,
      );
    });
  });

  group('append', () {
    test('adds to the end without changing the input', () {
      final history = [at(Duration.zero, 1)];
      final next = ValueHistory.append(
        history,
        at(const Duration(hours: 1), 2),
      );
      expect(next.map((s) => s.valueCents), [1, 2]);
      expect(history, hasLength(1));
    });

    test('caps at 2,000 by dropping the oldest', () {
      var history = <ValueSnapshot>[];
      for (var i = 0; i < ValueHistory.maxSnapshots + 5; i++) {
        history = ValueHistory.append(history, at(Duration(minutes: i), i));
      }
      expect(history, hasLength(2000));
      expect(history.first.valueCents, 5);
      expect(history.last.valueCents, 2004);
    });
  });
}
