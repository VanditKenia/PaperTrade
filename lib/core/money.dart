import 'package:intl/intl.dart';

import '../domain/models/stock.dart';

/// Converts an API price (double dollars) to int cents — the only place a
/// double price becomes money.
int toCents(double price) => (price * 100).round();

final _currency = NumberFormat.currency(locale: 'en_US', symbol: r'$');

/// 123456 → "$1,234.56", -123456 → "-$1,234.56".
String formatCents(int cents) => _currency.format(cents / 100);

/// 1.254 → "+1.25%", -0.5 → "-0.50%", 0 → "0.00%".
String formatPercent(double value) {
  final digits = value.abs().toStringAsFixed(2);
  // Check the rounded text so -0.001 shows "0.00%" rather than "-0.00%".
  final sign = digits == '0.00' ? '' : (value > 0 ? '+' : '-');
  return '$sign$digits%';
}

/// Change vs a base price, e.g. "▲ +$1.25 (+0.66%)". Arrow and sign mean
/// gains/losses are never shown by color alone.
String formatChange(int changeCents, int baseCents) {
  final arrow = changeCents > 0 ? '▲ ' : (changeCents < 0 ? '▼ ' : '');
  final sign = changeCents > 0 ? '+' : (changeCents < 0 ? '-' : '');
  final percent = baseCents > 0 ? changeCents / baseCents * 100 : 0.0;
  return '$arrow$sign${formatCents(changeCents.abs())} '
      '(${formatPercent(percent)})';
}

/// P&L style: 2210 → "+$22.10", -500 → "-$5.00", 0 → "$0.00".
String formatSignedCents(int cents) =>
    '${cents > 0 ? '+' : ''}${formatCents(cents)}';

/// "1 share" / "5 shares"; crypto: "1 unit" / "5 units".
String formatQuantity(String symbol, int qty) {
  final unit = isCrypto(symbol) ? 'unit' : 'share';
  return '$qty $unit${qty == 1 ? '' : 's'}';
}

/// Compact form for list rows: "5 sh"; crypto: "Qty 5".
String formatQuantityShort(String symbol, int qty) =>
    isCrypto(symbol) ? 'Qty $qty' : '$qty sh';
