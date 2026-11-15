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

/// The order's value rounds to 0 cents (e.g. 0.0001 of a $40 stock).
class OrderTooSmall extends TradeError {
  const OrderTooSmall();
}

/// Limit/stop price missing or not above 0.
class InvalidOrderPrice extends TradeError {
  const InvalidOrderPrice();
}

/// The order was already filled or cancelled.
class OrderNotFound extends TradeError {
  const OrderNotFound();
}

/// The price doesn't meet the order's limit/stop condition.
class OrderNotTriggered extends TradeError {
  const OrderNotTriggered();
}

/// Starting balance outside $100 – $10,000,000 or not whole dollars. Not a
/// TradeError: it comes from a reset, not a trade.
class InvalidStartingBalance implements Exception {
  const InvalidStartingBalance();
}
