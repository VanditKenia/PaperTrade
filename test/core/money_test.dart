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

  group('formatQuantity', () {
    test('stocks use shares, crypto uses units', () {
      expect(formatQuantity('AAPL', 10000), '1 share');
      expect(formatQuantity('AAPL', 50000), '5 shares');
      expect(formatQuantity('AAPL', 15000), '1.5 shares');
      expect(formatQuantity('BINANCE:BTCUSDT', 10000), '1 unit');
      expect(formatQuantity('BINANCE:BTCUSDT', 20000), '2 units');
      expect(formatQuantityShort('AAPL', 50000), '5 sh');
      expect(formatQuantityShort('BINANCE:BTCUSDT', 1), 'Qty 0.0001');
    });
  });

  test('formatShares: up to 4 decimals, trailing zeros trimmed', () {
    expect(formatShares(0), '0');
    expect(formatShares(1), '0.0001');
    expect(formatShares(10000), '1');
    expect(formatShares(15000), '1.5');
    expect(formatShares(12340), '1.234');
    expect(formatShares(5279273), '527.9273');
    expect(formatShares(10010), '1.001');
  });

  group('parseShares', () {
    test('parses exactly into units', () {
      expect(parseShares('1'), 10000);
      expect(parseShares('1.5'), 15000);
      expect(parseShares('0.0001'), 1);
      expect(parseShares('2.'), 20000);
      expect(parseShares('.25'), 2500);
      expect(parseShares('527.9273'), 5279273);
    });

    test('rejects junk and more than 4 decimals', () {
      for (final bad in ['', '.', 'abc', '-1', '1.23456', '1.2.3', '1e3']) {
        expect(parseShares(bad), isNull, reason: bad);
      }
    });
  });

  test('parseDollars: cents, max 2 decimals', () {
    expect(parseDollars('500'), 50000);
    expect(parseDollars('12.5'), 1250);
    expect(parseDollars('0.01'), 1);
    expect(parseDollars('1.234'), isNull);
    expect(parseDollars(''), isNull);
  });
}
