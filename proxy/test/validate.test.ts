import { describe, expect, it } from "vitest";
import { cacheKey, isRouteError, route, upstreamUrl, type Route } from "../src/validate";

const r = (path: string) => route(new URL(`https://proxy.test${path}`));
const ok = (path: string): Route => {
  const out = r(path);
  if (isRouteError(out)) throw new Error(`expected a route for ${path}: ${out.error}`);
  return out;
};

describe("routes", () => {
  it("quote: valid symbols incl. class shares and crypto", () => {
    for (const s of ["AAPL", "BRK.B", "BINANCE:BTCUSDT"]) {
      expect(ok(`/quote?symbol=${s}`)).toMatchObject({
        upstream: "finnhub",
        path: "/api/v1/quote",
        params: { symbol: s },
        ttlSeconds: 15,
      });
    }
  });

  it("quote: rejects bad symbols", () => {
    for (const s of ["", "aapl", "AAPL;DROP", "../x", "A".repeat(31), "%20AAPL"]) {
      expect(r(`/quote?symbol=${encodeURIComponent(s)}`)).toEqual({
        status: 400,
        error: "invalid symbol",
      });
    }
  });

  it("search: trims, fixes exchange=US, caches 1 h", () => {
    expect(ok("/search?q=%20apple%20inc%20")).toMatchObject({
      path: "/api/v1/search",
      params: { q: "apple inc", exchange: "US" },
      ttlSeconds: 3600,
    });
    expect(ok("/search?q=Nestl%C3%A9").params.q).toBe("Nestlé");
  });

  it("search: rejects empty, too long and odd characters", () => {
    for (const q of ["", "   ", "a".repeat(51), "<script>", "a&b=c|d"]) {
      expect(r(`/search?q=${encodeURIComponent(q)}`)).toEqual({
        status: 400,
        error: "invalid query",
      });
    }
  });

  it("search: the caller can't override the exchange", () => {
    expect(ok("/search?q=tesla&exchange=XX").params.exchange).toBe("US");
  });

  it("market-status: fixed params, 60 s", () => {
    expect(ok("/market-status?exchange=LSE")).toEqual({
      upstream: "finnhub",
      path: "/api/v1/stock/market-status",
      params: { exchange: "US" },
      ttlSeconds: 60,
    });
  });

  it("history: allowed intervals; 5min (1D) 5 min cache, others 1 h", () => {
    expect(ok("/history?symbol=AAPL&interval=5min&outputsize=78")).toMatchObject({
      upstream: "twelvedata",
      path: "/time_series",
      params: { symbol: "AAPL", interval: "5min", outputsize: "78", timezone: "UTC" },
      ttlSeconds: 300,
    });
    for (const interval of ["1h", "1day", "1week"]) {
      expect(ok(`/history?symbol=BTC/USD&interval=${interval}&outputsize=30`).ttlSeconds).toBe(
        3600,
      );
    }
  });

  it("history: rejects bad interval, size and symbol", () => {
    expect(r("/history?symbol=AAPL&interval=1min&outputsize=10")).toEqual({
      status: 400,
      error: "invalid interval",
    });
    for (const size of ["0", "501", "1.5", "x", ""]) {
      expect(r(`/history?symbol=AAPL&interval=1day&outputsize=${size}`)).toEqual({
        status: 400,
        error: "invalid outputsize",
      });
    }
    expect(r("/history?symbol=BINANCE:BTCUSDT&interval=1day&outputsize=10")).toEqual({
      status: 400,
      error: "invalid symbol",
    });
  });

  it("anything else is 404", () => {
    for (const p of ["/", "/api/v1/quote?symbol=AAPL", "/profile?symbol=AAPL", "/quote/AAPL"]) {
      expect(r(p)).toEqual({ status: 404, error: "not found" });
    }
  });
});

describe("cacheKey", () => {
  it("ignores param order and extra params", () => {
    const a = ok("/history?symbol=AAPL&interval=1day&outputsize=30");
    const b = ok("/history?outputsize=30&junk=1&interval=1day&symbol=AAPL");
    expect(cacheKey("https://p.test", a)).toBe(cacheKey("https://p.test", b));
  });

  it("never contains a key", () => {
    expect(cacheKey("https://p.test", ok("/quote?symbol=AAPL"))).not.toMatch(/token|apikey/);
  });
});

describe("upstreamUrl", () => {
  const keys = { finnhub: "fh-secret", twelveData: "td-secret" };

  it("adds the Finnhub token server-side", () => {
    const url = upstreamUrl(ok("/quote?symbol=AAPL"), keys);
    expect(url.origin).toBe("https://finnhub.io");
    expect(url.pathname).toBe("/api/v1/quote");
    expect(url.searchParams.get("token")).toBe("fh-secret");
    expect(url.searchParams.get("symbol")).toBe("AAPL");
  });

  it("adds the Twelve Data key server-side", () => {
    const url = upstreamUrl(ok("/history?symbol=AAPL&interval=1h&outputsize=35"), keys);
    expect(url.origin).toBe("https://api.twelvedata.com");
    expect(url.searchParams.get("apikey")).toBe("td-secret");
    expect(url.searchParams.has("token")).toBe(false);
  });
});
