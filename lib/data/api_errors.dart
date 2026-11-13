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
  const AuthError() : super('API key invalid — check configuration');
}

class RateLimitError extends ApiError {
  const RateLimitError() : super('Too many requests, try again shortly');
}

// Named with "Error" to avoid clashing with the domain's trade-time
// PriceUnavailable; this one means the API had no price for the symbol.
class PriceUnavailableError extends ApiError {
  const PriceUnavailableError() : super('Price unavailable for this symbol');
}

class UnknownError extends ApiError {
  const UnknownError() : super('Something went wrong. Retry');
}

/// Message for any error a screen might receive.
String errorMessage(Object error) =>
    error is ApiError ? error.message : const UnknownError().message;
