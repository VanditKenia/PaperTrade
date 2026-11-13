# API Specification

Primary provider: **Finnhub** (https://finnhub.io/docs/api). Free tier.

> ⚠️ Verify endpoints and free-tier limits on the Finnhub docs page when starting Step 0 — provider plans change.

## 1. Auth

- REST: query param `token=API_KEY` (or header `X-Finnhub-Token`)
- WebSocket: `wss://ws.finnhub.io?token=API_KEY`
- Key supplied at build time — see SECURITY.md

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

## 4. Optional: historical chart (F4b)

Finnhub `/stock/candle` is a paid endpoint. If adding a 1-month chart, use **Twelve Data** free tier:

`GET https://api.twelvedata.com/time_series?symbol=AAPL&interval=1day&outputsize=30&apikey=KEY`

```json
{ "values": [ { "datetime": "2026-11-11", "open": "...", "high": "...", "low": "...", "close": "189.42", "volume": "..." } ], "status": "ok" }
```
Note values are **strings** — parse to double. Verify current free-tier limits on their site.

## 5. Error mapping

| Condition | App error | UI message |
|---|---|---|
| No network / SocketException | `NetworkError` | "You're offline" |
| 401 / 403 | `AuthError` | "API key invalid — check configuration" |
| 429 | `RateLimitError` | "Too many requests, try again shortly" |
| Quote all zeros | `PriceUnavailable` | "Price unavailable for this symbol" |
| Other | `UnknownError` | "Something went wrong. Retry" |
