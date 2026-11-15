# API Specification

Primary provider: **Finnhub** (https://finnhub.io/docs/api). Free tier.

**Since Step 14 the app never calls Finnhub or Twelve Data directly.** It calls our Cloudflare Worker (§0), which adds the keys. §1–§4 describe the upstream APIs the Worker talks to.

## 0. Our proxy (what the app calls)

Base: `PROXY_BASE_URL` (e.g. `https://papertrade-proxy.<name>.workers.dev`), https / wss only. No key, no custom headers.

| App call | Proxy request | Upstream | Validation | Cache |
|---|---|---|---|---|
| `FinnhubApi.quote` | `GET /quote?symbol=AAPL` | Finnhub `/quote` | `^[A-Z0-9][A-Z0-9.:-]{0,29}$` | 15 s |
| `FinnhubApi.search` | `GET /search?q=apple` | Finnhub `/search` (Worker adds `exchange=US`) | trimmed, 1–50 chars of letters, digits, space `. & ' -` | 1 h |
| `FinnhubApi.isMarketOpen` | `GET /market-status` | Finnhub `/stock/market-status?exchange=US` | — | 60 s |
| `TwelveDataApi.timeSeries` | `GET /history?symbol=AAPL&interval=1day&outputsize=30` | Twelve Data `/time_series` (Worker adds `timezone=UTC`) | symbol `^[A-Z0-9][A-Z0-9.-]{0,14}(/[A-Z]{2,5})?$`, interval ∈ `5min, 1h, 1day, 1week`, outputsize 1–500 | 5 min for `5min` (1D), 1 h otherwise |
| `PriceStreamService` | `wss://<proxy>/ws` | one shared Finnhub WebSocket | same subscribe/unsubscribe JSON as §3; symbol format as `/quote`; max 50 symbols per client | — |

Responses: the upstream JSON unchanged, plus `X-Proxy-Cache: HIT | MISS`. Errors are `{"error": "..."}`:

| Status | When | App maps to |
|---|---|---|
| 400 | invalid params | `UnknownError` (history: `HistoryUnavailableError`) |
| 403 | browser `Origin` not allowed | `AuthError` |
| 404 | any other path or method | `UnknownError` |
| 429 | > 60 requests/min from one IP (`Retry-After`), or upstream 429 | `RateLimitError` |
| 401 / 403 | upstream rejected the key | `AuthError` |
| 502 | upstream unreachable or other upstream error | `UnknownError` |
| 503 | the Worker has no key for that upstream | history: `HistoryUnavailableError`; others: `UnknownError` |

WebSocket relay: trade messages are forwarded only for the symbols that client subscribed to; pings stay at the relay. Errors come as `{"type":"error","msg":"max 50 symbols per client" | "relay is at its symbol limit" | "invalid message"}`. If the upstream drops, the relay reconnects with backoff (1 → 30 s) and re-subscribes the union; the client socket stays open.

> ⚠️ Verify endpoints and free-tier limits on the Finnhub docs page when starting Step 0 — provider plans change.

## 1. Auth

- REST: query param `token=API_KEY` — added by the Worker, never by the app
- WebSocket: `wss://ws.finnhub.io?token=API_KEY` — opened only by the relay Durable Object
- Keys are Worker secrets — see SECURITY.md §2

## 2. REST endpoints

Base URL: `https://finnhub.io/api/v1`

### 2.1 Symbol search
`GET /search?q={query}&exchange=US`

```json
{
  "count": 2,
  "result": [
    { "description": "APPLE INC", "displaySymbol": "AAPL", "symbol": "AAPL", "type": "Common Stock" }
  ]
}
```
Filter to `type == "Common Stock"` (and ETFs if desired). Debounce 400 ms.

### 2.2 Quote
`GET /quote?symbol=AAPL`

```json
{ "c": 189.42, "d": 1.25, "dp": 0.6643, "h": 190.02, "l": 187.55, "o": 188.10, "pc": 188.17, "t": 1731430000 }
```
| Field | Meaning |
|---|---|
| c | current price |
| d / dp | change / change % vs previous close |
| h / l / o | day high / low / open |
| pc | previous close |
| t | unix seconds |

A response of all zeros means unknown symbol → treat as "price unavailable".
Cache per symbol for 30 s.

### 2.3 Company profile (optional, for name/logo)
`GET /stock/profile2?symbol=AAPL` → `{ "name": "Apple Inc", "logo": "https://...", "exchange": "...", "ticker": "AAPL", ... }`

### 2.4 Market status (optional, F11)
`GET /stock/market-status?exchange=US` → `{ "isOpen": true, "session": "regular", ... }`

### Rate limits
- **60 calls/min** on free tier. HTTP **429** on exceed → back off 60 s.
- Strategy: on app start fetch quotes for watchlist + holdings in one burst (≤ 20 symbols), then rely on WebSocket.

## 3. WebSocket

URL: `wss://ws.finnhub.io?token=API_KEY`

**Subscribe** (send one message per symbol):
```json
{"type":"subscribe","symbol":"AAPL"}
```
**Unsubscribe:**
```json
{"type":"unsubscribe","symbol":"AAPL"}
```
**Incoming trade message:**
```json
{
  "type": "trade",
  "data": [
    { "s": "AAPL", "p": 189.43, "t": 1731430001234, "v": 100, "c": null }
  ]
}
```
| Field | Meaning |
|---|---|
| s | symbol |
| p | last trade price |
| t | unix **milliseconds** |
| v | volume |

Other messages: `{"type":"ping"}` (ignore / keep-alive), `{"type":"error","msg":"..."}`.

Notes:
- A single message can contain **many trades** — take the last one per symbol.
- No ticks arrive when the US market is closed. Use `BINANCE:BTCUSDT` to test 24/7.
- Free limit: **50 symbols** subscribed at once.
- Re-send all subscribe messages after every reconnect.

## 4. Historical chart — Twelve Data (Step 8)

Finnhub `/stock/candle` is a paid endpoint, so history comes from the **Twelve Data** free tier
(8 requests/min, 800/day — re-check on their site).

`GET https://api.twelvedata.com/time_series?symbol=AAPL&interval=1day&outputsize=30&timezone=UTC&apikey=KEY`

- Key: Worker secret `TWELVE_DATA_API_KEY` (same rules as the Finnhub key). Missing → the proxy answers 503 and the chart shows "History unavailable"; live ticks still work.
- Build the URL with `Uri.https` + `queryParameters`. Timeout 10 s.
- `timezone=UTC` so `datetime` can be parsed as UTC and shown in local time.

```json
{ "meta": { ... },
  "values": [ { "datetime": "2026-11-11 15:55:00", "open": "...", "high": "...", "low": "...", "close": "189.42", "volume": "..." } ],
  "status": "ok" }
```
- Values are **strings**, newest first. Parse `close` to int cents; skip rows with a bad date or price; sort oldest first.
- Errors come either as an HTTP status or as HTTP 200 with `{"status":"error","code":429,"message":"..."}`. Use `code` when present.

| Code | App error |
|---|---|
| 400 / 404 (bad or unsupported symbol) | `HistoryUnavailableError` — "History unavailable" |
| 401 / 403 | `AuthError` |
| 429 | `RateLimitError` |
| network / timeout | `NetworkError` |
| other | `UnknownError` |

**Symbol mapping:** `BINANCE:BTCUSDT` → `BTC/USD` (any `BINANCE:<X>USDT` → `<X>/USD`); US stocks unchanged.

**Ranges**

| Chip | interval | outputsize | Cache TTL |
|---|---|---|---|
| 1D | 5min | 78 for stocks (one session, then only the newest session's bars are kept); 288 for crypto (last 24 h) | 5 min |
| 1W | 1h | 35 for stocks (5 sessions × 7 hourly bars); 168 for crypto | 1 h |
| 1M | 1day | 30 | 1 h |
| 6M | 1day | 130 | 1 h |
| 1Y | 1week | 52 | 1 h |

**Rate limit:** the app sends at most **8 requests per rolling 60 s**; beyond that it fails fast with "Too many requests, try again shortly" (no request sent). After a server 429 it backs off 60 s.

## 5. Error mapping

| Condition | App error | UI message |
|---|---|---|
| No network / SocketException | `NetworkError` | "You're offline" |
| 401 / 403 | `AuthError` | "Market data access denied — check configuration" |
| 429 | `RateLimitError` | "Too many requests, try again shortly" |
| Quote all zeros | `PriceUnavailable` | "Price unavailable for this symbol" |
| No Twelve Data key, or symbol not covered | `HistoryUnavailableError` | "History unavailable" |
| Other | `UnknownError` | "Something went wrong. Retry" |
