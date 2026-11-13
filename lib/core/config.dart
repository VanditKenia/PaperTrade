/// Finnhub API key, injected at build time:
///   flutter run --dart-define=FINNHUB_API_KEY=xxxx
/// Never hardcode or log this value (SECURITY.md §2).
const finnhubApiKey = String.fromEnvironment('FINNHUB_API_KEY');

bool get hasApiKey => finnhubApiKey.isNotEmpty;
