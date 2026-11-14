/// Finnhub API key, injected at build time:
///   flutter run --dart-define=FINNHUB_API_KEY=xxxx
/// Never hardcode or log this value (SECURITY.md §2).
const finnhubApiKey = String.fromEnvironment('FINNHUB_API_KEY');

bool get hasApiKey => finnhubApiKey.isNotEmpty;

// shortcut: copied by hand from pubspec.yaml; use package_info_plus if the
// two ever drift.
const appVersion = '1.0.0';
