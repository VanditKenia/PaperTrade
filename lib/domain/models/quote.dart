/// Day stats for a symbol from Finnhub `/quote`. Money fields are cents.
class Quote {
  const Quote({
    required this.symbol,
    required this.currentCents,
    required this.changeCents,
    required this.changePercent,
    required this.highCents,
    required this.lowCents,
    required this.openCents,
    required this.prevCloseCents,
    required this.timestamp,
  });

  final String symbol;
  final int currentCents; // c
  final int changeCents; // d
  final double changePercent; // dp — a percentage, not money, so double is fine
  final int highCents; // h
  final int lowCents; // l
  final int openCents; // o
  final int prevCloseCents; // pc
  final DateTime timestamp;
}
