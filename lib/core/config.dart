/// Base URL of our Cloudflare Worker (proxy/), injected at build time:
///   `flutter run --dart-define=PROXY_BASE_URL=https://papertrade-proxy.<name>.workers.dev`
/// The app holds no API keys: the Worker adds them (SECURITY.md §2).
const proxyBaseUrl = String.fromEnvironment('PROXY_BASE_URL');

/// The proxy, or null if PROXY_BASE_URL is missing or invalid.
final Uri? proxyUri = parseProxyUri(proxyBaseUrl);

/// False → the app shows the setup screen instead of starting.
bool get hasProxy => proxyUri != null;

/// Only a bare `https://host[:port]` is accepted (SECURITY.md §3), so the
/// clients can build every URL with `Uri.https(authority, path, …)`.
Uri? parseProxyUri(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    return null;
  }
  return Uri.https(uri.authority);
}

// shortcut: copied by hand from pubspec.yaml; use package_info_plus if the
// two ever drift.
const appVersion = '1.0.0';
