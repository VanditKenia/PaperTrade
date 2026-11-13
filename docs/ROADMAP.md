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

## Future steps (after placement)

Limit/stop-loss orders · price alerts (local notifications) · NSE/BSE data · performance analytics · iOS build on a Mac · backend proxy for the API key.
