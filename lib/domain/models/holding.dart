import '../quantity.dart';

/// Shares of one symbol the user owns.
class Holding {
  const Holding({
    required this.symbol,
    required this.quantity,
    required this.costBasisCents,
  });

  final String symbol;
  final int quantity; // units of 1/10,000 share (see quantity.dart)
  // Total cents paid for the shares still held. Stored instead of a rounded
  // avg per share so cost and realized P&L stay exact to the cent.
  final int costBasisCents;

  /// Average cost per whole share, for display.
  int get avgCostCents => mulDivHalfUp(costBasisCents, unitsPerShare, quantity);
}
