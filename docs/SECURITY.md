# Security

PaperTrade handles **no real money, no accounts, and no personal data**. The security goals are: protect the API key, keep local data intact, and never let bad input corrupt the portfolio.

## 1. Threat model (what could go wrong)

| Threat | Impact | Mitigation |
|---|---|---|
| API key committed to GitHub | Key abused, quota exhausted | Key never in source; `--dart-define`; `.gitignore`; secret scan before push |
| API key extracted from the APK | Same as above | Accepted risk for a demo (free key, read-only). Production: proxy through a backend (see §6) |
| Invalid order input (negative qty, huge numbers, text) | Corrupt portfolio | Validate in UI **and** in PortfolioEngine (defense in depth) |
| Malformed API / WebSocket data | Crash or wrong prices | Defensive JSON parsing; reject non-positive / non-finite prices; try/catch per message |
| Man-in-the-middle | Fake prices | HTTPS + WSS only; no cleartext traffic allowed |
| Data loss / corruption on crash | Lost portfolio | Atomic state writes; engine returns full new state before saving |
| Misleading the user about real money | Trust / legal | Clear "virtual money" labelling on first launch, Settings, and README |

## 2. API key handling

1. Run/build with:
   ```bash
   flutter run --dart-define=FINNHUB_API_KEY=xxxx
   ```
   Read in code:
   ```dart
   const finnhubApiKey = String.fromEnvironment('FINNHUB_API_KEY');
   ```
   If empty → show a clear setup error screen, not a crash.
2. **Never** hardcode the key, never put it in `pubspec.yaml`, never log it.
3. Optionally use `--dart-define-from-file=env.json` and add `env.json` to `.gitignore`. Commit an `env.example.json` with a placeholder.
4. Before every push: `git grep -i "token=\|apikey\|FINNHUB"` must not show a real key.
5. If a key ever leaks: regenerate it in the Finnhub dashboard immediately.

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
- Do not log full request URLs (they contain the token).

## 4. Input validation

Quantity field:
- Digits only (`FilteringTextInputFormatter.digitsOnly`), max 7 digits.
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

## 7. Production hardening (future, not v1.0)

- Move API calls behind a small backend proxy that holds the key; app talks to proxy only.
- Certificate pinning for the proxy.
- Code obfuscation: `flutter build apk --obfuscate --split-debug-info=build/symbols`.
- Dependency audit: `flutter pub outdated`, review new packages before adding.

## 8. Pre-push checklist

- [ ] No API key in code, commits, screenshots, or README
- [ ] `flutter analyze` clean
- [ ] `flutter test` passes
- [ ] App shows "virtual money" disclaimer
