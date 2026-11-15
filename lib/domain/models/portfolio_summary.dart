/// Derived totals for the portfolio screen. Computed from live prices,
/// never stored.
class PortfolioSummary {
  const PortfolioSummary({
    required this.cashCents,
    required this.investedCents,
    required this.marketValueCents,
    required this.unrealizedPnlCents,
    required this.portfolioValueCents,
    required this.totalReturnCents,
    required this.totalReturnPercent,
    required this.startingCashCents,
  });

  final int cashCents;
  final int investedCents; // Σ cost basis — what the holdings cost
  final int marketValueCents; // Σ cost(qty, livePrice)
  final int unrealizedPnlCents; // marketValue - invested
  final int portfolioValueCents; // cash + marketValue
  final int totalReturnCents; // portfolioValue - startingCash
  final double totalReturnPercent;
  final int startingCashCents;
}
