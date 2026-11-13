/// Why a trade was rejected. `sealed` lets the UI `switch` over every case
/// and the compiler complains if one is missed.
sealed class TradeError implements Exception {
  const TradeError();
}

class InsufficientFunds extends TradeError {
  const InsufficientFunds();
}

class InsufficientShares extends TradeError {
  const InsufficientShares();
}

class InvalidQuantity extends TradeError {
  const InvalidQuantity();
}

class PriceUnavailable extends TradeError {
  const PriceUnavailable();
}
