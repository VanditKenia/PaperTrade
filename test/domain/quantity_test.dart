import 'package:flutter_test/flutter_test.dart';
import 'package:papertrade/domain/quantity.dart';

void main() {
  group('costCents', () {
    test('whole shares are exact', () {
      expect(costCents(5 * unitsPerShare, 18942), 94710);
    });

    test('rounds half up', () {
      expect(costCents(5000, 18943), 9472); // 9471.5 → 9472
      expect(costCents(1, 5000), 1); // 0.5 → 1
      expect(costCents(1, 4999), 0); // 0.4999 → 0
      expect(costCents(3333, 10000), 3333);
      expect(costCents(1, 14999), 1); // 1.4999 → 1
    });

    test('no overflow for large quantity × price', () {
      // 9,999,999.9999 shares × $10,000,000.00: product > 2^63.
      expect(costCents(99999999999, 1000000000), 9999999999900000);
    });
  });

  test('mulDivHalfUp', () {
    expect(mulDivHalfUp(7, 1, 2), 4); // 3.5 → 4
    expect(mulDivHalfUp(5, 1, 3), 2); // 1.67 → 2
    expect(mulDivHalfUp(4, 1, 3), 1); // 1.33 → 1
    expect(mulDivHalfUp(0, 5, 3), 0);
  });

  group('maxAffordableUnits', () {
    test('is the largest quantity whose cost fits', () {
      for (final (cash, price) in [
        (10000000, 18942),
        (1, 100),
        (0, 100),
        (999, 3),
        (123456, 9999999),
      ]) {
        final u = maxAffordableUnits(cash, price);
        expect(costCents(u, price), lessThanOrEqualTo(cash));
        expect(costCents(u + 1, price), greaterThan(cash));
      }
    });

    test(r'$100,000 at $189.42 → 527.9273 shares', () {
      expect(maxAffordableUnits(10000000, 18942), 5279273);
    });
  });

  test('unitsForAmount rounds down so the cost never exceeds the amount', () {
    expect(unitsForAmount(50000, 18942), 26396); // $500 → 2.6396 sh
    expect(costCents(26396, 18942), lessThanOrEqualTo(50000));
    expect(unitsForAmount(1, 18942), 0);
  });
}
