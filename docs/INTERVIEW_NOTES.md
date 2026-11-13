# Interview Notes

## The 30-second pitch

> "I wanted to practice trading before using real money, so I built PaperTrade — a Flutter app that streams **live US stock prices over WebSocket** and lets you trade with **$100,000 of virtual money**. It has a watchlist, search, live charts, a buy/sell order flow, and a portfolio with real-time P&L. The trading logic is a pure, unit-tested engine, money is stored as integer cents, and live updates are throttled so the UI stays smooth even when prices tick many times a second."

## Resume bullets (pick 2–3)

**PaperTrade — Stock Trading Simulator** | Flutter, Dart, Riverpod, WebSocket, REST, Hive | [GitHub link]
- Built a cross-platform (Android/iOS) paper-trading app streaming **real-time stock prices via WebSocket** (Finnhub), with search, watchlist, live charts and a $100K virtual portfolio.
- Designed a **pure, immutable portfolio engine** (weighted average cost, realized/unrealized P&L) using integer-cent arithmetic; covered with **15+ unit tests**.
- **Throttled high-frequency price ticks** to 2 UI updates/sec with per-row rebuilds, and added auto-reconnect with exponential backoff for resilient live data.
- Layered architecture (UI → state → repository → data source) with offline caching and local persistence.

Only claim what you actually built and tested.

## Concepts you must explain without notes

1. **WebSocket vs REST polling** — server pushes updates over one persistent connection; lower latency and fewer requests than polling every second.
2. **Throttling** — ticks are buffered in a map (latest price per symbol); a timer emits a snapshot every 500 ms. Prevents rebuilding UI 50×/sec.
3. **`select()` in Riverpod** — each row listens only to its own symbol's price, so one price change rebuilds one row, not the whole list.
4. **Why int cents** — `0.1 + 0.2 = 0.30000000000000004` in floating point. Financial systems use integers or decimal types.
5. **Weighted average cost** — `(oldQty×oldAvg + newQty×price) / (oldQty+newQty)`. Selling doesn't change avg cost.
6. **Realized vs unrealized P&L** — realized is locked in on a sell; unrealized is on open positions at the live price.
7. **Reconnect with exponential backoff** — 1s, 2s, 4s… up to 30s; prevents hammering the server; re-subscribe after reconnect.
8. **Immutable engine** — a trade either fully applies (new state) or fails (typed error). No half-applied trades; easy to test.
9. **API key security** — not in source; passed with dart-define; a client app can't fully hide a key, so production would use a backend proxy.
10. **Architecture layers** — why UI doesn't call APIs directly (testability, swap data sources).

## Likely questions & answers

**Why Flutter for an iOS role?**
I don't have a Mac yet, and Flutter let me target iOS and Android from one codebase. The concepts map directly: Flutter widgets ≈ SwiftUI views, Riverpod notifiers ≈ ObservableObject view models, Streams ≈ Combine/AsyncStream, web_socket_channel ≈ URLSessionWebSocketTask. I'm keen to go deeper into Swift and UIKit/SwiftUI.

**What was the hardest part?**
Keeping the UI smooth under fast price updates — solved with throttling + selective rebuilds. (Or: getting average-cost math right — solved with tests first.)

**How would you scale this to a real trading app like IBKR's?**
Backend for auth, orders and the API key; order types (limit, stop); order book/market depth; server-confirmed fills instead of local fills; secure token storage; certificate pinning; heavy testing and monitoring.

**What happens if the WebSocket disconnects mid-session?**
The app shows the last known prices, displays "Reconnecting…", retries with backoff, re-subscribes all symbols, and trading is disabled while prices are unknown.

**How did you test it?**
Unit tests on the engine with a worked example, parsing and throttle tests, widget tests on the order sheet, plus a manual QA checklist including offline mode.

**Did you use AI tools?**
Yes, I used Claude Code as a coding assistant, building feature by feature. I wrote the specs, reviewed and tested every part, and can walk through any file.

## Know IB

Interactive Brokers: global online broker; flagship apps are **IBKR Mobile** and **IBKR GlobalTrader**; offers its own **paper trading accounts**. Mentioning that your app mirrors the paper-trading concept shows you researched the company.
