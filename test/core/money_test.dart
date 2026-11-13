import 'package:flutter_test/flutter_test.dart';
import 'package:papertrade/core/money.dart';

void main() {
  group('formatCents', () {
    test('formats with dollar sign and thousands separator', () {
      expect(formatCents(123456), r'$1,234.56');
      expect(formatCents(0), r'$0.00');
      expect(formatCents(5), r'$0.05');
    });

    test('formats negative values', () {
      expect(formatCents(-123456), r'-$1,234.56');
    });
  });

  group('toCents', () {
    test('rounds to the nearest cent', () {
      expect(toCents(189.425), 18943);
      expect(toCents(100), 10000);
      expect(toCents(0.1 + 0.2), 30);
    });
  });

  group('formatPercent', () {
    test('adds sign and 2 decimals', () {
      expect(formatPercent(1.254), '+1.25%');
      expect(formatPercent(-0.5), '-0.50%');
      expect(formatPercent(0), '0.00%');
      expect(formatPercent(-0.001), '0.00%');
    });
  });
}
