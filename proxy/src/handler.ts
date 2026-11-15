// REST + WebSocket entry point. Dependencies are passed in so tests can use
// a fake upstream, cache and clock without the Workers runtime.

import { corsHeaders, isAllowedOrigin } from "./cors";
import type { RateLimiter } from "./rate_limit";
import { cacheKey, isRouteError, route, upstreamUrl } from "./validate";

export interface Env {
  FINNHUB_API_KEY?: string; // wrangler secret
  TWELVE_DATA_API_KEY?: string; // wrangler secret
  ALLOWED_ORIGINS?: string; // wrangler.toml [vars]
  RELAY: DurableObjectNamespace;
}

export interface CacheLike {
  match(key: string): Promise<Response | undefined>;
  put(key: string, response: Response): Promise<void>;
}

export interface Deps {
  fetch: typeof fetch;
  cache: CacheLike;
  limiter: RateLimiter;
  waitUntil: (p: Promise<unknown>) => void;
}

const UPSTREAM_TIMEOUT_MS = 10_000;

export async function handle(request: Request, env: Env, deps: Deps): Promise<Response> {
  const origin = request.headers.get("Origin");
  // CORS alone only stops a page from *reading* the answer; refusing
  // other origins outright also stops them spending our quota.
  if (origin !== null && !isAllowedOrigin(origin, env.ALLOWED_ORIGINS ?? "")) {
    return json({ error: "origin not allowed" }, 403, null);
  }
  if (request.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }
  if (request.method !== "GET") return json({ error: "not found" }, 404, origin);

  const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
  const limit = deps.limiter.hit(ip);
  if (!limit.allowed) {
    const res = json({ error: "too many requests" }, 429, origin);
    res.headers.set("Retry-After", String(limit.retryAfterSeconds));
    return res;
  }

  const url = new URL(request.url);
  if (url.pathname === "/ws") {
    if (request.headers.get("Upgrade") !== "websocket") {
      return json({ error: "expected websocket" }, 426, origin);
    }
    // Every client goes to the same object, which owns the one upstream
    // socket a free Finnhub key allows.
    const relay = env.RELAY.get(env.RELAY.idFromName("relay"));
    return relay.fetch(request);
  }

  const r = route(url);
  if (isRouteError(r)) return json({ error: r.error }, r.status, origin);

  const key = r.upstream === "finnhub" ? env.FINNHUB_API_KEY : env.TWELVE_DATA_API_KEY;
  // 503 for a missing secret: the app shows "History unavailable" for
  // Twelve Data, so the chart degrades instead of erroring.
  if (!key) return json({ error: "not configured" }, 503, origin);

  const ck = cacheKey(url.origin, r);
  const cached = await deps.cache.match(ck);
  if (cached !== undefined) return withHeaders(cached, origin, "HIT");

  let upstream: Response;
  try {
    upstream = await deps.fetch(
      upstreamUrl(r, {
        finnhub: env.FINNHUB_API_KEY ?? "",
        twelveData: env.TWELVE_DATA_API_KEY ?? "",
      }),
      { signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS) },
    );
  } catch {
    // Deliberately no details: the error could include the URL (and key).
    return json({ error: "upstream unreachable" }, 502, origin);
  }

  // Auth and rate-limit problems keep their status so the app shows the
  // right message; anything else is a bad gateway.
  if (!upstream.ok) {
    const status = [401, 403, 429].includes(upstream.status) ? upstream.status : 502;
    return json({ error: "upstream error" }, status, origin);
  }

  const body = await upstream.text();
  if (isCacheable(body)) {
    deps.waitUntil(
      deps.cache.put(
        ck,
        new Response(body, {
          headers: {
            "Content-Type": "application/json",
            "Cache-Control": `public, max-age=${r.ttlSeconds}`,
          },
        }),
      ),
    );
  }
  return withHeaders(
    new Response(body, { headers: { "Content-Type": "application/json" } }),
    origin,
    "MISS",
  );
}

// Twelve Data reports errors as HTTP 200 with {"status":"error"}; caching
// those would hide a recovered upstream for up to an hour.
function isCacheable(body: string): boolean {
  try {
    const parsed: unknown = JSON.parse(body);
    return !(
      typeof parsed === "object" &&
      parsed !== null &&
      (parsed as Record<string, unknown>).status === "error"
    );
  } catch {
    return false;
  }
}

function withHeaders(res: Response, origin: string | null, cache: "HIT" | "MISS"): Response {
  const out = new Response(res.body, { status: res.status, headers: res.headers });
  for (const [k, v] of Object.entries(corsHeaders(origin))) out.headers.set(k, v);
  out.headers.set("X-Proxy-Cache", cache);
  // The app caches on its own; browsers shouldn't add another layer.
  out.headers.set("Cache-Control", "no-store");
  return out;
}

function json(body: unknown, status: number, origin: string | null): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders(origin) },
  });
}
