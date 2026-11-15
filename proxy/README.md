# papertrade-proxy

Cloudflare Worker (free plan) that keeps the market-data API keys off the
client. The app only knows this Worker's URL; the Worker adds the Finnhub /
Twelve Data keys server-side.

| Route | Forwards to | Validation | Cache |
|---|---|---|---|
| `GET /quote?symbol=AAPL` | Finnhub `/api/v1/quote` | symbol `^[A-Z0-9][A-Z0-9.:-]{0,29}$` | 15 s |
| `GET /search?q=apple` | Finnhub `/api/v1/search` (exchange=US) | 1–50 chars: letters, digits, space `. & ' -` | 1 h |
| `GET /market-status` | Finnhub `/api/v1/stock/market-status` (exchange=US) | — | 60 s |
| `GET /history?symbol=AAPL&interval=1day&outputsize=30` | Twelve Data `/time_series` (timezone=UTC) | symbol (e.g. `BTC/USD`), interval ∈ 5min/1h/1day/1week, outputsize 1–500 | 5 min for 5min, else 1 h |
| `GET /ws` (WebSocket) | one shared Finnhub WebSocket | Finnhub-style subscribe/unsubscribe JSON, max 50 symbols per client | — |

Anything else → 404. Per-IP limit: 60 requests/min → 429 + `Retry-After`.
Browser origins: `http://localhost:*`, `http://127.0.0.1:*` and the exact
origins in `ALLOWED_ORIGINS` (`wrangler.toml`); other origins → 403.
Requests without an `Origin` (the Android app, curl) are allowed.

Code: `src/validate.ts` (routes), `src/cors.ts`, `src/rate_limit.ts`,
`src/handler.ts` (REST + cache), `src/subscriptions.ts` + `src/relay.ts`
(WebSocket relay Durable Object), `src/index.ts` (entry).

## Develop

```bash
cd proxy
npm install
npm test            # Vitest: validation, routing, cache, CORS, rate limit, subscriptions
npm run typecheck
```

Local run (optional): put the keys in `proxy/.dev.vars` (gitignored)

```
FINNHUB_API_KEY=...
TWELVE_DATA_API_KEY=...
```

then `npx wrangler dev` and `curl "http://localhost:8787/quote?symbol=AAPL"`.
The app itself only talks https/wss, so point it at the deployed Worker.

## Deploy (free plan)

```bash
cd proxy
npm install
npx wrangler login                          # opens the browser once
npx wrangler secret put FINNHUB_API_KEY     # paste the key at the prompt
npx wrangler secret put TWELVE_DATA_API_KEY # paste the key at the prompt
npx wrangler deploy                         # prints https://papertrade-proxy.<subdomain>.workers.dev
```

If `secret put` asks whether to create the Worker first, answer yes. Keys
are typed at the prompt, so they never land in shell history or files.
If you host the web build, put its origin in `ALLOWED_ORIGINS` in
`wrangler.toml` and deploy again.

## Check the deployed proxy

```bash
P=https://papertrade-proxy.<subdomain>.workers.dev

curl "$P/quote?symbol=AAPL"                              # {"c":…,"d":…}
curl "$P/search?q=apple"                                 # {"count":…,"result":[…]}
curl "$P/market-status"                                  # {"isOpen":…}
curl "$P/history?symbol=AAPL&interval=1day&outputsize=5" # {"meta":…,"values":[…]}

curl -s -o /dev/null -w "%{http_code}\n" "$P/nope"                 # 404
curl -s -o /dev/null -w "%{http_code}\n" "$P/quote?symbol=bad!"    # 400
curl -s -o /dev/null -w "%{http_code}\n" -H "Origin: https://evil.example" "$P/market-status"  # 403

# Cache: second call says HIT (on *.workers.dev the Cache API may be a
# no-op, then both say MISS; it works on a custom domain)
curl -sI "$P/quote?symbol=MSFT" | grep -i x-proxy-cache
curl -sI "$P/quote?symbol=MSFT" | grep -i x-proxy-cache

# Rate limit: the last few of 65 calls are 429
for i in $(seq 1 65); do curl -s -o /dev/null -w "%{http_code}\n" "$P/market-status"; done | sort | uniq -c

# WebSocket relay (BTC trades 24/7)
npx wscat -c "wss://papertrade-proxy.<subdomain>.workers.dev/ws"
#   > {"type":"subscribe","symbol":"BINANCE:BTCUSDT"}
#   < {"type":"trade","data":[{"s":"BINANCE:BTCUSDT","p":…}]}

npx wrangler tail   # live request log (the Worker never logs keys or upstream URLs)
```

Then run the app against it:

```bash
flutter run -d chrome --dart-define=PROXY_BASE_URL=$P
```

## Limits worth knowing

- Rate limiting is per Worker isolate (in memory), so it's approximate.
- The relay is one Durable Object: about 11,000 of the free plan's
  13,000 GB-s/day if a client stays connected 24/7. It drops the upstream
  socket when the last client leaves so the object can sleep.
- Finnhub free keys allow 50 symbols on the one upstream socket; beyond
  that, new symbols get `{"type":"error","msg":"relay is at its symbol limit"}`.
