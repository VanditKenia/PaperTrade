/// Network/API failures mapped per API_SPEC.md §5. Each carries the message
/// the UI shows, so screens don't need their own error-to-text mapping.
sealed class ApiError implements Exception {
  const ApiError(this.message);

  final String message;
}

class NetworkError extends ApiError {
  const NetworkError([super.message = "You're offline"]);
}

class AuthError extends ApiError {
  // 401/403: the proxy refused us (origin not allowed) or its key was
  // rejected upstream. Either way it's configuration, not the user.
  const AuthError() : super('Market data access denied — check configuration');
}

class RateLimitError extends ApiError {
  const RateLimitError() : super('Too many requests, try again shortly');
}

// Named with "Error" to avoid clashing with the domain's trade-time
// PriceUnavailable; this one means the API had no price for the symbol.
class PriceUnavailableError extends ApiError {
  const PriceUnavailableError() : super('Price unavailable for this symbol');
}

/// The proxy has no Twelve Data key, or the symbol isn't on the free tier.
class HistoryUnavailableError extends ApiError {
  const HistoryUnavailableError() : super('History unavailable');
}

class UnknownError extends ApiError {
  const UnknownError() : super('Something went wrong. Retry');
}

/// Message for any error a screen might receive.
String errorMessage(Object error) =>
    error is ApiError ? error.message : const UnknownError().message;
