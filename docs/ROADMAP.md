# Roadmap — Step-by-Step Build Plan

Build **one step at a time**. After each step: run the app, read the code, ask Claude Code to explain anything unclear, run tests, then **commit**.

Each step has a ready-to-paste Claude Code prompt.

---

## Tonight's timeline (deadline: tomorrow 4 PM)

| Time (IST) | Step |
|---|---|
| 9:30 – 10:00 PM | Step 0 — setup |
| 10:00 – 11:00 PM | Step 1 — domain + engine + tests |
| 11:00 – 12:00 AM | Step 2 — watchlist + quotes + search |
| 12:00 – 1:00 AM | Step 3 — live WebSocket prices |
| 1:00 – 2:00 AM | Step 4 — stock detail + chart |
| *sleep* | |
| 8:30 – 10:00 AM | Step 5 — order sheet + portfolio + persistence |
| 10:00 – 11:00 AM | Step 6 — history, settings, polish |
| 11:00 AM – 12:30 PM | Step 7 — README, screenshots, demo video, push |
| 12:30 – 3:30 PM | Update resume, study code, buffer |

US market is open roughly 8:00 PM–2:30 AM IST — good for testing live ticks tonight.

**Minimum viable for the resume:** Steps 0–5. Steps 6–7 make it shine.

---

## Step 0 — Project setup
**Done when:** app runs on emulator showing a placeholder home with bottom nav; API key loads from dart-define.

> Read all the .md files in /docs (PRD, TRD, ARCHITECTURE, APP_FLOW, UI_UX, API_SPEC, SECURITY, TESTING, CLAUDE.md). Create a new Flutter project called `papertrade` following ARCHITECTURE.md's folder structure. Add dependencies from TRD.md (flutter_riverpod, hive_ce, hive_ce_flutter, http, web_socket_channel, fl_chart, intl; dev: mocktail, fake_async). Set up `core/config.dart` to read FINNHUB_API_KEY via String.fromEnvironment and show a setup-error screen if empty. Set up the dark theme from UI_UX.md in `core/theme.dart`. Create an app shell with bottom navigation (Watchlist, Portfolio, History, Settings) with placeholder screens. Add .gitignore entries from SECURITY.md and an env.example.json. Don't build any features yet. Explain the structure when done.

Commit: `chore: project setup, theme, navigation shell`

---

## Step 1 — Domain models + PortfolioEngine + tests
**Done when:** `flutter test` passes all PortfolioEngine tests from TESTING.md.

> Implement Step 1 from ROADMAP.md. Create the domain models from TRD.md §3 (money as int cents) and `core/money.dart` (toCents, formatCents, formatPercent). Implement `domain/portfolio_engine.dart` as pure immutable Dart (no Flutter imports) with buy, sell, reset and summary calculations exactly per TRD.md §4, and typed errors in trade_errors.dart. Write all unit tests listed in TESTING.md §2 and §3 (money), including the worked example. Run the tests. Then explain the weighted average cost formula and why we use int cents.

Commit: `feat: portfolio engine with unit tests`

---

## Step 2 — Finnhub REST, watchlist, search
**Done when:** watchlist shows default stocks with real prices; search works; can add/remove; watchlist persists.

> Implement Step 2 from ROADMAP.md. Build `data/finnhub_api.dart` (search + quote per API_SPEC.md, with error mapping §5 and 10s timeout, using Uri queryParameters). Build `data/local_store.dart` with Hive for the watchlist. Build `market_repository.dart` with 30s quote caching. Build watchlist_provider and WatchlistScreen per UI_UX.md §3.1 with default symbols from APP_FLOW.md §2, pull-to-refresh, swipe-to-remove, loading/empty/error states. Build SearchScreen with 400ms debounce and add/remove star. Keep UI out of the data layer. Explain the data flow from screen to API.

Commit: `feat: watchlist and stock search with Finnhub REST`

---

## Step 3 — Live prices over WebSocket
**Done when:** prices update live on the watchlist with a flash effect; reconnects after toggling airplane mode.

> Implement Step 3 from ROADMAP.md. Build `data/price_stream_service.dart` per API_SPEC.md §3: connect, subscribe/unsubscribe, parse trade messages defensively (latest price per symbol, ignore ping, skip malformed), auto-reconnect with exponential backoff and re-subscribe, close on app background and reconnect on resume. Build `core/throttle.dart` and emit a Map<String,int> snapshot at most every 500 ms (ARCHITECTURE.md §3). Expose livePricesProvider. Make each PriceTile watch only its own symbol using select, and add the 300ms price flash. Sync subscriptions with the watchlist. Add the throttle and parsing tests from TESTING.md §3. Explain throttling and why select() matters.

Commit: `feat: real-time prices via WebSocket with throttling and reconnect`

---

## Step 4 — Stock detail + chart
**Done when:** tapping a stock shows live price, day stats, and a live-updating line chart.

> Implement Step 4 from ROADMAP.md. Build StockDetailScreen per UI_UX.md §3.3: header with live price and change, day stats from quote, a fl_chart line chart built from ticks collected while the screen is open (seed with prevClose and open so it's never empty), green/red by day direction, star toggle, and a sticky Buy/Sell bar (buttons can be placeholders for now). Navigate from watchlist and search. Explain how the chart data is collected.

Commit: `feat: stock detail screen with live chart`

*(Optional F4b, only if time: 1-month daily chart using Twelve Data per API_SPEC.md §4.)*

---

## Step 5 — Trading: order sheet, portfolio, persistence
**Done when:** full buy → portfolio → sell flow works with live P&L and survives app restart.

> Implement Step 5 from ROADMAP.md. Build portfolio_repository (Hive: wallet, holdings, trades — save whole state atomically after a successful engine call) and portfolioProvider with buy/sell/reset using PortfolioEngine. Build the OrderSheet per UI_UX.md §3.4 (qty stepper, digits-only input, Max chip, live cost/cash-after preview, inline validation, realized P&L preview for sells, haptic + snackbar on success). Show the user's position on StockDetail. Build PortfolioScreen per UI_UX.md §3.5 with portfolioSummaryProvider recomputing from live prices. First launch creates $100,000 wallet. Add widget tests from TESTING.md §4. Explain the trade flow end to end.

Commit: `feat: paper trading with order sheet, portfolio and persistence`

---

## Step 6 — History, settings, polish
**Done when:** history lists trades; reset works; offline banner and market status show.

> Implement Step 6 from ROADMAP.md. Build HistoryScreen per UI_UX.md §3.6 and SettingsScreen per §3.7 with a confirmed Reset account. Add the offline banner, "Reconnecting…" indicator, market-status chip (API_SPEC.md §2.4), first-launch info banner, tabular figures on all prices, and AnimatedSwitcher on changing numbers. Go through APP_FLOW.md §5 edge flows and make sure each is handled. Run flutter analyze and fix all warnings.

Commit: `feat: trade history, settings, offline and polish`

---

## Step 7 — Ship it
**Done when:** public GitHub repo with README, screenshots, demo video, all tests green.

> Implement Step 7 from ROADMAP.md. Update README.md with: one-line description, feature list, screenshots section (placeholders I'll fill), architecture diagram from ARCHITECTURE.md, tech stack, how to run with dart-define, testing instructions, and "virtual money only" disclaimer. Run the SECURITY.md pre-push checklist and confirm no API key is anywhere in the repo or git history.

Then manually:
1. Take 4 screenshots: Watchlist, Stock Detail, Order Sheet, Portfolio.
2. Record a 60–90 s screen video: search → buy → live P&L → sell.
3. `flutter build apk --release --dart-define=FINNHUB_API_KEY=...` (keep the APK for demos; don't publish it with your key).
4. Push to GitHub; pin the repo on your profile.

Commit: `docs: README, screenshots, demo`

---

## Step 8 — Multi-timeframe historical chart
**Done when:** Stock Detail shows 1D · 1W · 1M · 6M · 1Y charts from Twelve Data, 1D keeps updating with live ticks, and the app still works without a Twelve Data key.

> Implement Step 8 from ROADMAP.md. Build `data/twelve_data_api.dart` per API_SPEC.md §4 (`/time_series` with symbol, interval, outputsize, apikey via `Uri.https`; key from `String.fromEnvironment('TWELVE_DATA_API_KEY')`, never logged; 10 s timeout; string values parsed defensively to int cents; errors mapped to ApiError; symbol mapping BINANCE:BTCUSDT → BTC/USD). Build `data/history_repository.dart` with an in-memory cache (1D: 5 min, others: 1 h) and a guard of at most 8 requests per minute. Add `historyProvider(symbol, range)` as a family AsyncNotifier that never depends on the portfolio. On StockDetail add range chips 1D · 1W · 1M · 6M · 1Y (default 1D) per UI_UX.md §3.3: straight-segment line, y-axis fitted to the data, green/red by first vs last price, header change for the selected range, touch crosshair with price and date/time, live ticks appended on 1D, loading skeleton, error + Retry, empty state. Missing key → "History unavailable", live ticks still shown. Test parsing, symbol mapping, cache hit/expiry, the rate-limit guard and the provider with a fake API. Explain the caching and rate-limit design.

Commit: `feat: multi-timeframe historical chart via Twelve Data`

---

## Step 9 — Custom starting balance
**Done when:** first launch asks for a starting balance, Reset lets you pick a new one, and total return is measured against it.

> Implement Step 9 from ROADMAP.md. Store `startingCashCents` in PortfolioState and persist it in the same single Hive value (old saved data without it loads as $100,000). `PortfolioEngine.reset(startingCashCents)`; summary total return = portfolio value − starting cash (and % vs starting cash). Validate in the engine and the UI: whole dollars, $100 – $10,000,000, typed error otherwise. First launch (no saved portfolio): "Choose your starting balance" screen with presets $1K / $10K / $50K / $100K / $1M and a custom digits-only field, then Watchlist. Settings → Reset account: same presets + field, pre-filled with the current starting balance, then confirm. Show "Starting balance $X" in the Portfolio header. Test reset with a custom amount, total return vs a custom start, validation bounds, migration of old data, and the onboarding and reset dialog widgets.

Commit: `feat: custom starting balance`

---

## Step 10 — Fractional quantities
**Done when:** you can buy and sell fractions of a share (down to 0.0001), by quantity or by dollar amount, with cash, avg cost and P&L exact to the cent, and old saved portfolios still load.

> Implement Step 10 from ROADMAP.md. Store every quantity (holdings, trades, engine) as `int` units of 1/10,000 share (`unitsPerShare = 10000` in `domain/quantity.dart`). One helper computes money from quantity: `costCents(units, priceCents) = units × price / 10,000`, rounded half up, in int math; cash, cost basis, market value and the order preview all use it. Keep weighted average cost and realized P&L exact: holdings store their total cost basis in cents (avg cost is derived for display); a sell removes a proportional share of the basis (all of it when selling everything) and realized P&L = proceeds − removed basis. Reject orders whose value rounds to 0 cents (`OrderTooSmall`). Migrate saved data: data without version `v: 2` has whole-share quantities × 10,000 and basis = qty × avg. Order sheet per UI_UX.md §3.4: decimal quantity input (max 4 decimals, min 0.0001), an "Amount ($)" mode that converts dollars to the largest quantity that costs no more, and Max that fills the exact affordable/owned quantity. Display quantities with up to 4 decimals, trailing zeros trimmed. Update all tests; add rounding, migration and exactness tests.

Commit: `feat: fractional quantities`

---

## Step 11 — Limit & stop-loss orders
**Done when:** you can place a limit buy, limit sell or stop-loss sell, see and cancel it under "Open orders" on Portfolio, and it fills on a live tick while the app is open, with reserved cash/shares that can't be spent twice.

> Implement Step 11 from ROADMAP.md. Order types per TRD.md §4: Market (existing), Limit Buy (fills when price ≤ limit), Limit Sell (price ≥ limit), Stop-Loss Sell (price ≤ stop). Pending orders reserve resources: limit buys reserve cash (cost at the limit), sells reserve quantity; available cash = cash − reserved, available quantity = held − in open sell orders; market trades and new orders check against available amounts. Fill at the triggering tick price. Keep it pure Dart: `PendingOrder.triggersAt`, `OrderMatcher` (ticks = changed prices, triggered orders), `PortfolioEngine.placeOrder / cancelOrder / fillOrder`. Persist open orders and each trade's fill type in the same atomic portfolio value (older data: no orders, trades = market). Add `orderMatcherProvider`, kept alive by AppShell, that listens to live prices and calls `portfolioProvider.notifier.fillOrder(id, priceCents:)`; the portfolio notifier still never reads prices. Serialize notifier changes so a fill and a user trade can't overwrite each other. Subscribe open-order symbols on the socket. Orders only execute while the app is open: say so in the order sheet and the Open orders section. Order sheet: Market / Limit (/ Stop-loss for sells) selector, price field with validation. Portfolio: "Open orders" with Cancel. History: show how each trade filled. Tests: trigger rules, reservations, cancel, partial availability, persistence, and provider tests with fake ticks.

Commit: `feat: limit and stop-loss orders`

---

## Step 12 — Performance stats
**Done when:** Portfolio → Stats shows realized P&L, trade count, win rate, average win/loss, best/worst trade and a portfolio-value-over-time chart, with empty states, and the value history survives a restart.

> Implement Step 12 from ROADMAP.md. Build a pure-Dart `PerformanceCalculator` over the trade list: total realized P&L (Σ sells), number of trades (buys + sells), win rate (sells with realized P&L > 0 ÷ sells; break-even counts as a sell but not a win), average win, average loss (int cents, half up), best and worst trade (highest/lowest realized P&L; earliest wins ties). Record portfolio value snapshots on every trade and at most every 5 minutes while the app is open, capped at 2,000 (oldest dropped), persisted under their own Hive key; an account reset clears them. Recording lives in a separate `snapshotRecorderProvider` (reads the price-based summary, watches the portfolio, nothing reads it back) so the portfolio notifier still never reads prices. Add a Stats screen reachable from the Portfolio app bar with these numbers and a portfolio-value line chart (reuse PriceChart), per UI_UX.md §3.5b, with empty states. Unit tests for every metric, the snapshot rules, persistence, the recorder (fake time) and the screen.

Commit: `feat: performance stats`

---

## Step 13 — Price alerts
**Done when:** on Stock Detail you can set "rises above $X" / "falls below $X"; while the app is open the first live tick that crosses it shows a snackbar (and an Android notification), the alert is marked triggered and never fires again, alerts survive a restart, and you can delete them on Stock Detail and in Settings.

> Implement Step 13 from ROADMAP.md. `PriceAlert { id, symbol, direction (above | below), targetCents, createdAt, triggeredAt?, triggeredPriceCents? }`. Pure `AlertRules`: `crosses(alert, previous, current)` (above: previous < target ≤ current; below: previous > target ≥ current; previous null = first price since opening → fires if already past), `triggered(alerts, previousSnapshot, nextSnapshot)` (waiting alerts only, changed prices only), and `targetError` (target must be ahead of the current price). Persist alerts under their own Hive key. `alertMonitorProvider` (kept alive by AppShell) listens to live prices, marks each fired alert triggered (state first, then save, so it can't fire twice), pushes it to `lastTriggeredAlertProvider` (AppShell shows the snackbar) and calls `NotificationService.show` — flutter_local_notifications on Android only (permission requested when creating an alert), a no-op elsewhere. Subscribe waiting-alert symbols on the socket. UI per UI_UX.md §3.3/§3.3b/§3.7: "Add alert" sheet and alerts list with delete on Stock Detail, all alerts in Settings, and "Alerts only work while the app is open" in both. Tests: crossing and fire-once rules, persistence, the monitor with fake ticks, sheet/list/snackbar widgets.

Commit: `feat: price alerts`

---

## Step 14 — API key proxy (Cloudflare Worker)
**Done when:** the app contains no API key; all REST and WebSocket traffic goes through our Worker (deployed on the free plan) using `PROXY_BASE_URL`; the Worker forwards only the four REST calls the app makes plus a shared WebSocket relay, with caching, per-IP rate limiting and strict CORS.

> Implement Step 14 from ROADMAP.md. New `proxy/` folder: TypeScript Cloudflare Worker with Wrangler. Secrets `FINNHUB_API_KEY` and `TWELVE_DATA_API_KEY` via `wrangler secret put`, never in code or logs. REST routes `/quote`, `/search`, `/market-status` (Finnhub) and `/history` (Twelve Data) only: validate params (symbol format, allowed intervals, outputsize), add the key server-side, return upstream JSON; anything else 404. Cache with the Cache API (quote 15 s, market-status 60 s, search 1 h, history 5 min for 1D / 1 h otherwise). WebSocket relay at `/ws`: one Durable Object holds ONE upstream Finnhub socket, subscribes it to the union of client subscriptions (unsubscribe when no client needs a symbol), fans trades out to the clients that want them, reconnects with backoff; same subscribe/unsubscribe JSON as Finnhub, max symbols per client. Per-IP rate limit (60/min → 429). CORS: localhost (dev) and our web origin only, no wildcard, no credentials. Vitest for validation, routing, rate limiting and subscription union. App: replace both keys with `PROXY_BASE_URL` (dart-define; empty or not https → setup screen); point finnhub_api, twelve_data_api and price_stream_service at the proxy (https/wss only); update env.example.json and all tests. Docs: ARCHITECTURE, SECURITY §1/§2/§7, API_SPEC, README.

Commit: `feat: API key proxy on Cloudflare Workers`

---

## Future steps (after placement)

Orders and price alerts that work while the app is closed (needs a backend) · more analytics (drawdown, per-symbol stats) · NSE/BSE data · iOS build on a Mac.
