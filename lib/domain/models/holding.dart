/// Shares of one symbol the user owns.
class Holding {
  const Holding({
    required this.symbol,
    required this.quantity,
    required this.avgCostCents,
  });

  final String symbol;
  final int quantity; // whole shares
  final int avgCostCents; // average cost per share
}
