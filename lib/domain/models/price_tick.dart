/// One live trade price from the WebSocket.
class PriceTick {
  const PriceTick({
    required this.symbol,
    required this.priceCents,
    required this.time,
  });

  final String symbol;
  final int priceCents;
  final DateTime time;
}
