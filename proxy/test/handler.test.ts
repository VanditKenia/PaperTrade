import { beforeEach, describe, expect, it, vi } from "vitest";
import { isAllowedOrigin } from "../src/cors";
import { type CacheLike, type Deps, type Env, handle } from "../src/handler";
import { RateLimiter } from "../src/rate_limit";

const ORIGIN = "https://papertrade.example";

class MemoryCache implements CacheLike {
  readonly store = new Map<string, string>();
  async match(key: string) {
    const body = this.store.get(key);
    return body === undefined ? undefined : new Response(body);
  }
  async put(key: string, response: Response) {
    this.store.set(key, await response.text());
  }
}

let env: Env;
let deps: Deps;
let cache: MemoryCache;
let upstream: ReturnType<typeof vi.fn>;
let pending: Promise<unknown>[];

beforeEach(() => {
  env = {
    FINNHUB_API_KEY: "fh-secret",
    TWELVE_DATA_API_KEY: "td-secret",
    ALLOWED_ORIGINS: ORIGIN,
    RELAY: {} as DurableObjectNamespace,
  };
  cache = new MemoryCache();
  upstream = vi.fn(async () => new Response('{"c":189.42}', { status: 200 }));
  pending = [];
  deps = {
    fetch: upstream as unknown as typeof fetch,
    cache,
    limiter: new RateLimiter(60, 60_000, () => 0),
    waitUntil: (p) => pending.push(p),
  };
});

async function get(path: string, headers: Record<string, string> = {}, method = "GET") {
  const res = await handle(
    new Request(`https://proxy.test${path}`, {
      method,
      headers: { "CF-Connecting-IP": "1.2.3.4", ...headers },
    }),
    env,
    deps,
  );
  await Promise.all(pending);
  return res;
}

describe("routing", () => {
  it("forwards a quote with the key added server-side, returns upstream JSON", async () => {
    const res = await get("/quote?symbol=AAPL");
    expect(res.status).toBe(200);
    expect(await res.text()).toBe('{"c":189.42}');
    const called = new URL(String(upstream.mock.calls[0]![0]));
    expect(called.host).toBe("finnhub.io");
    expect(called.searchParams.get("token")).toBe("fh-secret");
  });

  it("the key never appears in what the client gets", async () => {
    const res = await get("/quote?symbol=AAPL");
    const all = JSON.stringify([...res.headers]) + (await res.text());
    expect(all).not.toContain("fh-secret");
  });

  it("unknown paths and non-GET are 404, without calling upstream", async () => {
    expect((await get("/api/v1/quote?symbol=AAPL")).status).toBe(404);
    expect((await get("/quote?symbol=AAPL", {}, "POST")).status).toBe(404);
    expect(upstream).not.toHaveBeenCalled();
  });

  it("invalid params are 400, without calling upstream", async () => {
    const res = await get("/quote?symbol=bad;symbol");
    expect(res.status).toBe(400);
    expect(await res.json()).toEqual({ error: "invalid symbol" });
    expect(upstream).not.toHaveBeenCalled();
  });

  it("history goes to Twelve Data with apikey", async () => {
    await get("/history?symbol=AAPL&interval=1day&outputsize=30");
    const called = new URL(String(upstream.mock.calls[0]![0]));
    expect(called.host).toBe("api.twelvedata.com");
    expect(called.searchParams.get("apikey")).toBe("td-secret");
    expect(called.searchParams.get("timezone")).toBe("UTC");
  });

  it("missing secret → 503 (the app shows History unavailable)", async () => {
    env.TWELVE_DATA_API_KEY = undefined;
    expect((await get("/history?symbol=AAPL&interval=1day&outputsize=30")).status).toBe(503);
  });

  it("upstream auth/rate-limit statuses pass through, others become 502", async () => {
    for (const [up, out] of [
      [401, 401],
      [429, 429],
      [500, 502],
      [404, 502],
    ]) {
      upstream.mockResolvedValueOnce(new Response("{}", { status: up }));
      expect((await get(`/quote?symbol=S${up}`)).status).toBe(out);
    }
  });

  it("upstream unreachable → 502", async () => {
    upstream.mockRejectedValueOnce(new Error("boom https://finnhub.io?token=fh-secret"));
    const res = await get("/quote?symbol=AAPL");
    expect(res.status).toBe(502);
    expect(await res.text()).not.toContain("fh-secret");
  });

  it("/ws without an upgrade header → 426", async () => {
    expect((await get("/ws")).status).toBe(426);
  });
});

describe("cache", () => {
  it("second identical request is served from cache", async () => {
    expect((await get("/quote?symbol=AAPL")).headers.get("X-Proxy-Cache")).toBe("MISS");
    const second = await get("/quote?symbol=AAPL");
    expect(second.headers.get("X-Proxy-Cache")).toBe("HIT");
    expect(await second.text()).toBe('{"c":189.42}');
    expect(upstream).toHaveBeenCalledTimes(1);
  });

  it("errors are not cached, incl. Twelve Data's 200 + status:error", async () => {
    upstream.mockResolvedValueOnce(new Response('{"status":"error","code":429}'));
    await get("/history?symbol=AAPL&interval=1day&outputsize=30");
    upstream.mockResolvedValueOnce(new Response("{}", { status: 500 }));
    await get("/quote?symbol=AAPL");
    expect(cache.store.size).toBe(0);
  });
});

describe("rate limiting", () => {
  it("61st request in a minute from one IP → 429 with Retry-After", async () => {
    for (let i = 0; i < 60; i++) expect((await get("/market-status")).status).toBe(200);
    const res = await get("/market-status");
    expect(res.status).toBe(429);
    expect(res.headers.get("Retry-After")).toBe("60");
    expect((await get("/market-status", { "CF-Connecting-IP": "5.6.7.8" })).status).toBe(200);
  });
});

describe("CORS", () => {
  it("allowed origins get it echoed back, never * or credentials", async () => {
    for (const origin of [ORIGIN, "http://localhost:53124", "http://127.0.0.1:8080"]) {
      const res = await get("/market-status", { Origin: origin });
      expect(res.headers.get("Access-Control-Allow-Origin")).toBe(origin);
      expect(res.headers.get("Access-Control-Allow-Credentials")).toBeNull();
    }
  });

  it("other origins are refused before anything else", async () => {
    const res = await get("/quote?symbol=AAPL", { Origin: "https://evil.example" });
    expect(res.status).toBe(403);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBeNull();
    expect(upstream).not.toHaveBeenCalled();
  });

  it("no Origin (native app, curl) is allowed without CORS headers", async () => {
    const res = await get("/market-status");
    expect(res.status).toBe(200);
    expect(res.headers.get("Access-Control-Allow-Origin")).toBeNull();
  });

  it("preflight gets 204", async () => {
    expect((await get("/quote", { Origin: ORIGIN }, "OPTIONS")).status).toBe(204);
  });

  it("isAllowedOrigin: exact match only", () => {
    expect(isAllowedOrigin("https://papertrade.example.evil.com", ORIGIN)).toBe(false);
    expect(isAllowedOrigin("http://papertrade.example", ORIGIN)).toBe(false);
    expect(isAllowedOrigin("https://localhost:3000", "")).toBe(false); // https localhost isn't dev
    expect(isAllowedOrigin("http://localhost.evil.com", "")).toBe(false);
    expect(isAllowedOrigin("https://a.example", " https://a.example , https://b.example")).toBe(
      true,
    );
  });
});
