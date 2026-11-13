/// Derived totals for the portfolio screen. Computed from live prices,
/// never stored.
class PortfolioSummary {
  const PortfolioSummary({
    required this.cashCents,
    required this.marketValueCents,
    required this.unrealizedPnlCents,
    required this.portfolioValueCents,
    required this.totalReturnCents,
    required this.totalReturnPercent,
  });

  final int cashCents;
  final int marketValueCents; // Σ qty * livePrice
  final int unrealizedPnlCents; // Σ (livePrice - avgCost) * qty
  final int portfolioValueCents; // cash + marketValue
  final int totalReturnCents; // portfolioValue - startingCash
  final double totalReturnPercent;
}
