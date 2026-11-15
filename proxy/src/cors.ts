// Which browser origins may call the proxy. Native apps send no Origin
// header, so CORS doesn't apply to them.

const LOCALHOST = /^http:\/\/(localhost|127\.0\.0\.1)(:\d{1,5})?$/;

// `flutter run -d chrome` uses a random localhost port, so any port is
// allowed there; production origins must match exactly.
export function isAllowedOrigin(origin: string, allowedList: string): boolean {
  if (LOCALHOST.test(origin)) return true;
  return allowedList
    .split(",")
    .map((o) => o.trim())
    .filter((o) => o.length > 0)
    .includes(origin);
}

// Echo the one allowed origin (never "*") and no credentials header: the
// proxy uses no cookies, so browsers never send any.
export function corsHeaders(origin: string | null): Record<string, string> {
  if (origin === null) return {};
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
}
