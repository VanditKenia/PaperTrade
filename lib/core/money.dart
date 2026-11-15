import 'package:intl/intl.dart';

import '../domain/models/stock.dart';
import '../domain/quantity.dart';

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

/// Quantity units → up to 4 decimals without trailing zeros:
/// 50000 → "5", 15000 → "1.5", 1 → "0.0001".
String formatShares(int units) {
  final whole = units ~/ unitsPerShare;
  final fraction = units % unitsPerShare;
  if (fraction == 0) return '$whole';
  final digits = '$fraction'.padLeft(4, '0').replaceFirst(RegExp(r'0+$'), '');
  return '$whole.$digits';
}

/// "1 share" / "1.5 shares"; crypto: "1 unit" / "5 units".
String formatQuantity(String symbol, int units) {
  final unit = isCrypto(symbol) ? 'unit' : 'share';
  final plural = units == unitsPerShare ? '' : 's';
  return '${formatShares(units)} $unit$plural';
}

/// Compact form for list rows: "5 sh"; crypto: "Qty 5".
String formatQuantityShort(String symbol, int units) => isCrypto(symbol)
    ? 'Qty ${formatShares(units)}'
    : '${formatShares(units)} sh';

/// Typed shares → units, exactly (no double): "1.5" → 15000, "2." → 20000,
/// ".25" → 2500. Null if empty, not a number or more than 4 decimals.
int? parseShares(String text) => _parseFixed(text, 4);

/// Typed dollars → cents: "12.5" → 1250. Null like [parseShares], or for
/// more than 2 decimals.
int? parseDollars(String text) => _parseFixed(text, 2);

final _decimal = RegExp(r'^(\d*)(?:\.(\d*))?$');

int? _parseFixed(String text, int decimals) {
  final match = _decimal.firstMatch(text.trim());
  if (match == null) return null;
  final whole = match[1]!;
  final fraction = match[2] ?? '';
  if (whole.isEmpty && fraction.isEmpty) return null;
  if (fraction.length > decimals) return null;
  final w = int.tryParse(whole.isEmpty ? '0' : whole);
  final f = int.tryParse(fraction.padRight(decimals, '0'));
  if (w == null || f == null) return null;
  return w * int.parse('1'.padRight(decimals + 1, '0')) + f; // × 10^decimals
}

final _wholeDollars = NumberFormat.currency(
  locale: 'en_US',
  symbol: r'$',
  decimalDigits: 0,
);

/// Whole-dollar amounts like starting balances: 10000000 → "$100,000".
/// Drops the cents, so only use it where they are always zero.
String formatDollars(int cents) => _wholeDollars.format(cents ~/ 100);
