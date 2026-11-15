/// One point on a price chart: a historical close or a live tick.
class PricePoint {
  const PricePoint({required this.time, required this.priceCents});

  final DateTime time;
  final int priceCents;
}
