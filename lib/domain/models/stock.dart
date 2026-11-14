/// A search result or watchlist item.
class Stock {
  const Stock({required this.symbol, required this.name});

  final String symbol; // "AAPL"
  final String name; // "Apple Inc"
}

/// Crypto pairs trade 24/7 and are bought in units, not shares.
bool isCrypto(String symbol) => symbol.startsWith('BINANCE:');
