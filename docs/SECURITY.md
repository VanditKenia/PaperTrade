# Security

PaperTrade handles **no real money, no accounts, and no personal data**. The security goals are: protect the API keys, keep local data intact, and never let bad input corrupt the portfolio.

## 1. Threat model (what could go wrong)

| Threat | Impact | Mitigation |
|---|---|---|
| API key committed to GitHub | Key abused, quota exhausted | Keys exist only as Cloudflare Worker secrets (`wrangler secret put`); never in the repo, app, `wrangler.toml` or logs; secret scan before push |
| API key extracted from the APK / browser Network tab | Same as above | **Mitigated (Step 14):** the app holds no key, only `PROXY_BASE_URL`; the Worker adds keys server-side |
| Proxy abused as a free data API | Our quota exhausted | Only 4 REST routes + `/ws`, strict param validation, 60 req/min per IP, edge cache, CORS + Origin check (other browser origins get 403), max 50 symbols per WebSocket client |
| Proxy URL is public | Anyone can call it with curl | Accepted: the limits above cap the damage; it only serves public market data. Without accounts there is no secret the app could prove |
| Invalid order input (negative qty, huge numbers, text) | Corrupt portfolio | Validate in UI **and** in PortfolioEngine (defense in depth) |
| Malformed API / WebSocket data | Crash or wrong prices | Defensive JSON parsing; reject non-positive / non-finite prices; try/catch per message |
| Man-in-the-middle | Fake prices | HTTPS + WSS only; no cleartext traffic allowed |
| Data loss / corruption on crash | Lost portfolio | Atomic state writes; engine returns full new state before saving |
| Misleading the user about real money | Trust / legal | Clear "virtual money" labelling on first launch, Settings, and README |

## 2. API key handling

The **app contains no API key** (Step 14). Keys live only in the Cloudflare Worker (`proxy/`).

1. Store the keys as Worker secrets, typed at the prompt (not in shell history or files):
   ```bash
   cd proxy
   npx wrangler secret put FINNHUB_API_KEY
   npx wrangler secret put TWELVE_DATA_API_KEY
   ```
   For `wrangler dev` only: `proxy/.dev.vars` (gitignored).
2. The Worker adds the key to the upstream URL itself and **never logs** URLs, upstream errors or keys (errors to the client are generic, e.g. "upstream unreachable"). A missing secret answers 503, not a crash.
3. The app gets only the proxy URL at build time:
   ```bash
   flutter run --dart-define=PROXY_BASE_URL=https://papertrade-proxy.<name>.workers.dev
   ```
   ```dart
   const proxyBaseUrl = String.fromEnvironment('PROXY_BASE_URL');
   ```
   Empty or not a bare `https://host` → the setup error screen, not a crash. It isn't secret, but `env.json` stays gitignored; `env.example.json` has a placeholder.
4. Before every push: `git grep -iE "token=|apikey|FINNHUB_API_KEY=|TWELVE_DATA_API_KEY="` must not show a real key (only the `wrangler secret put` instructions).
5. If a key ever leaks: regenerate it in the provider's dashboard, then `wrangler secret put` the new one (takes effect immediately, no app release needed).

`.gitignore` must include:
```
env.json
*.env
.env*
```

## 3. Network

- Only `https://` and `wss://` URLs.
- Android: do **not** enable `usesCleartextTraffic`.
- iOS: no App Transport Security exceptions.
- Timeouts: REST 10 s. Never retry in a tight loop (exponential backoff).
- The app's URLs hold no key (Step 14). The Worker never logs upstream URLs: they contain the key.

## 4. Input validation

Quantity field:
- Digits and one dot only: any edit that doesn't match `^\d{0,7}(\.\d{0,4})?$` (shares) or `^\d{0,9}(\.\d{0,2})?$` (dollars) is rejected. Parsed to int units/cents with string math, never `double`.
- Must be integer ≥ 1.
- Buy: `qty * price <= cash`. Sell: `qty <= owned`.

PortfolioEngine re-checks every rule and throws typed errors — UI validation is for UX, engine validation is the real guard.

Search field: trim, max 50 chars, URL-encode before sending (`Uri` with `queryParameters`, never string concat).

## 5. Data parsing

- Treat every field from the network as untrusted: check type, null, `isFinite`, `> 0`.
- One bad WebSocket message must not kill the stream (try/catch per message, log and skip).
- Use integer cents internally — no float rounding drift in balances.

## 6. Local storage

- Hive stores: watchlist symbols, wallet cash, holdings, trades. **No PII.**
- Data is not sensitive, so no encryption needed in v1.0. (If accounts are added later, use `flutter_secure_storage` for tokens and encrypted Hive boxes.)
- Write the whole portfolio state in one operation after a successful engine call, so a crash can't leave cash debited without the holding added.
- Reset account requires a confirmation dialog.

## 7. Production hardening

Done (Step 14):
- API calls go through our Cloudflare Worker, which holds the keys; the app talks to the proxy only (https/wss).
- Proxy: route allowlist + param validation, per-IP rate limit (60/min, approximate: per isolate), Cache API (quote 15 s, market status 60 s, search 1 h, history 5 min / 1 h), CORS limited to localhost and `ALLOWED_ORIGINS` with no wildcard and no credentials, one shared upstream WebSocket with max 50 symbols per client.

Still future:
- Exact rate limiting (Cloudflare Rate Limiting binding or a Durable Object counter) and a custom domain (the Cache API is only guaranteed on custom domains, not `*.workers.dev`).
- App attestation (Play Integrity) so only the real app can call the proxy.
- Certificate pinning for the proxy.
- Code obfuscation: `flutter build apk --obfuscate --split-debug-info=build/symbols`.
- Dependency audit: `flutter pub outdated`, review new packages before adding.

## 8. Pre-push checklist

- [ ] No API key in code, commits, screenshots, or README
- [ ] `flutter analyze` clean
- [ ] `flutter test` passes
- [ ] App shows "virtual money" disclaimer
