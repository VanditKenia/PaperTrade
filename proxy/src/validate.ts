// Which requests the proxy forwards, and how. Pure: URL in, route out.
// Only the four calls the app makes exist; everything else is a 404.

export type Upstream = "finnhub" | "twelvedata";

export interface Route {
  upstream: Upstream;
  path: string; // upstream path
  params: Record<string, string>; // validated; the key is added later
  ttlSeconds: number; // cache lifetime
}

export interface RouteError {
  status: 400 | 404;
  error: string;
}

// Finnhub symbols: AAPL, BRK.B, BINANCE:BTCUSDT.
const FINNHUB_SYMBOL = /^[A-Z0-9][A-Z0-9.:-]{0,29}$/;
// Twelve Data symbols (the app maps crypto first): AAPL, BTC/USD.
const HISTORY_SYMBOL = /^[A-Z0-9][A-Z0-9.-]{0,14}(\/[A-Z]{2,5})?$/;
// Company names and tickers: letters, digits, space and . & ' -
const SEARCH_QUERY = /^[\p{L}\p{N} .&'-]{1,50}$/u;
// The intervals the app's chart ranges use (lib/data/history_repository.dart).
const INTERVALS = new Set(["5min", "1h", "1day", "1week"]);
const MAX_OUTPUT_SIZE = 500;

export function route(url: URL): Route | RouteError {
  const q = url.searchParams;
  switch (url.pathname) {
    case "/quote": {
      const symbol = q.get("symbol") ?? "";
      if (!FINNHUB_SYMBOL.test(symbol)) return bad("invalid symbol");
      return { upstream: "finnhub", path: "/api/v1/quote", params: { symbol }, ttlSeconds: 15 };
    }
    case "/search": {
      const query = (q.get("q") ?? "").trim();
      if (!SEARCH_QUERY.test(query)) return bad("invalid query");
      return {
        upstream: "finnhub",
        path: "/api/v1/search",
        params: { q: query, exchange: "US" },
        ttlSeconds: 3600,
      };
    }
    case "/market-status":
      // Fixed exchange: the app only asks about the US market.
      return {
        upstream: "finnhub",
        path: "/api/v1/stock/market-status",
        params: { exchange: "US" },
        ttlSeconds: 60,
      };
    case "/history": {
      const symbol = q.get("symbol") ?? "";
      const interval = q.get("interval") ?? "";
      const size = Number(q.get("outputsize"));
      if (!HISTORY_SYMBOL.test(symbol)) return bad("invalid symbol");
      if (!INTERVALS.has(interval)) return bad("invalid interval");
      if (!Number.isInteger(size) || size < 1 || size > MAX_OUTPUT_SIZE) {
        return bad("invalid outputsize");
      }
      return {
        upstream: "twelvedata",
        path: "/time_series",
        // UTC so the app can parse times without knowing the exchange.
        params: { symbol, interval, outputsize: String(size), timezone: "UTC" },
        // 5-minute bars are the 1D chart, which changes during the day.
        ttlSeconds: interval === "5min" ? 300 : 3600,
      };
    }
    default:
      return { status: 404, error: "not found" };
  }
}

export function isRouteError(r: Route | RouteError): r is RouteError {
  return "status" in r;
}

// Same request → same cache key, whatever the param order in the URL.
export function cacheKey(origin: string, r: Route): string {
  const sorted = Object.keys(r.params)
    .sort()
    .map((k) => `${encodeURIComponent(k)}=${encodeURIComponent(r.params[k]!)}`)
    .join("&");
  return `${origin}/cache/${r.upstream}${r.path}?${sorted}`;
}

// Upstream URL with the key added. Contains the secret: never log it.
export function upstreamUrl(r: Route, keys: { finnhub: string; twelveData: string }): URL {
  const url =
    r.upstream === "finnhub"
      ? new URL(`https://finnhub.io${r.path}`)
      : new URL(`https://api.twelvedata.com${r.path}`);
  for (const [k, v] of Object.entries(r.params)) url.searchParams.set(k, v);
  if (r.upstream === "finnhub") url.searchParams.set("token", keys.finnhub);
  else url.searchParams.set("apikey", keys.twelveData);
  return url;
}

function bad(error: string): RouteError {
  return { status: 400, error };
}
