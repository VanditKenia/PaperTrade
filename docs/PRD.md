# PRD — Product Requirements Document

**Product:** PaperTrade — Stock Trading Simulator
**Platform:** Android (primary), iOS (same Flutter codebase)
**Version:** 1.0 (MVP)
**Owner:** Vandit Kenia

---

## 1. Problem

Beginners want to learn stock trading, but practicing with real money is risky and expensive. Most simulators are web-only, cluttered, or use delayed/fake prices, so practice doesn't feel real.

## 2. Solution

A clean mobile app where users trade **real stocks at live market prices** using **virtual money**. Every buy and sell updates a portfolio with live profit/loss, so users learn how markets move without financial risk.

## 3. Target users

| Persona | Need |
|---|---|
| **Beginner investor** (primary) — student/young professional who has never traded | Learn how buying, selling, and P&L work before using real money |
| **Strategy tester** — knows basics, wants to test ideas | Fast order entry, clear portfolio performance |

## 4. Goals & success criteria

| Goal | Measure |
|---|---|
| Feels real | Prices update live (≤1s delay after a trade tick arrives) |
| Easy to use | New user can place first trade within 60 seconds of opening the app |
| Correct | Portfolio math (cash, average cost, P&L) is always correct — covered by unit tests |
| Reliable | App works offline with last known data; never loses portfolio data |

## 5. Scope

### In scope (MVP — v1.0)

| # | Feature | Priority |
|---|---|---|
| F1 | **Stock search** — search by symbol or company name | P0 |
| F2 | **Watchlist** — add/remove stocks, see price & daily change | P0 |
| F3 | **Live prices** — real-time updates via WebSocket | P0 |
| F4 | **Stock detail** — price, day stats, price chart | P0 |
| F5 | **Virtual wallet** — starts at $100,000 virtual cash | P0 |
| F6 | **Buy / Sell (market orders)** — at the live price, with validation | P0 |
| F7 | **Portfolio** — holdings, average cost, live unrealized P&L, total value | P0 |
| F8 | **Trade history** — list of all past trades | P1 |
| F9 | **Persistence** — watchlist, wallet, holdings, trades survive app restart | P0 |
| F10 | **Reset account** — restart with fresh $100,000 | P1 |
| F11 | **Market status** — show "Market open/closed" | P2 |
| F12 | **Limit & stop-loss orders** — limit buy/sell and stop-loss sell, open-orders list with cancel; fill on live ticks while the app is open | P2 |
| F13 | **Performance stats** — realized P&L, trade count, win rate, average win/loss, best/worst trade, portfolio value over time | P2 |
| F14 | **Price alerts** — "rises above / falls below $X" per stock; fires once on a live tick while the app is open; in-app snackbar, Android notification; list with delete | P2 |

### Out of scope (v1.0)

- Real money, payments, UPI, or broker integration
- User accounts / login / cloud sync
- Short selling, options; orders that fill while the app is closed
- Indian stocks (NSE/BSE) — free real-time data not available (future)
- Push notifications from a server; alerts that fire while the app is closed

### Future (v2+)

Server-side price alerts (fire while closed) · NSE/BSE support · leaderboard · deeper analytics (drawdown, per-symbol) · dark/light theme toggle

## 6. User stories

- As a user, I can **search** "apple" and find AAPL, so I can look at it.
- As a user, I can **add a stock to my watchlist** so I can follow its price.
- As a user, I see **prices change live** so it feels like the real market.
- As a user, I can open a stock and see a **chart** of its recent prices.
- As a user, I can **buy N shares** at the current price if I have enough virtual cash.
- As a user, I can **sell shares I own**, and the money goes back to my wallet.
- As a user, I can see my **portfolio value and P&L** update live.
- As a user, I can see a **history** of all my trades.
- As a user, my data is **still there after I close the app**.
- As a user, I can **reset** my account to start practicing again.

## 7. Business rules (summary — full detail in TRD.md)

1. Starting virtual cash: **chosen by the user** on first launch (and on reset): whole dollars from **$100 to $10,000,000**; presets $1K / $10K / $50K / $100K / $1M; default **$100,000**. Total return is measured against this amount.
2. Market orders fill instantly at the **latest known price**. Limit and stop-loss orders fill at the price of the live tick that triggers them: limit buy when price ≤ limit, limit sell when price ≥ limit, stop-loss sell when price ≤ stop. They only execute **while the app is open**.
3. Cannot buy more than *available* cash allows, or sell more than *available* shares. Open orders reserve what they need: a limit buy reserves its cost at the limit price, a sell order reserves its shares. Cancelling releases it.
4. Quantity can be fractional: up to 4 decimals, minimum 0.0001 share, or entered as a dollar amount. An order must be worth at least $0.01.
5. No fees or commissions in v1.0.
6. Performance stats are computed from trades: win rate = sells with a positive realized P&L ÷ all sells (break-even sells are neither wins nor losses); averages are in whole cents, rounded half up. The value chart records the portfolio value on every trade and at most every 5 minutes while the app is open (last 2,000 points); a reset starts it over.
7. A price alert fires **once**, on the first live tick that crosses its target (rises to/above, or falls to/below), and then stays in the list as triggered. The target must be on the far side of the current price when created. Alerts only work **while the app is open** (no backend).

## 8. Assumptions & constraints

- Data source: Finnhub free tier (US stocks, real-time trades; 60 REST calls/min).
- US market hours: 9:30 AM–4:00 PM ET ≈ **8:00 PM–2:30 AM IST** (7:00 PM–1:30 AM IST during US daylight saving). Outside these hours, prices are static (last price).
- For testing live updates outside US hours, crypto symbols (e.g. `BINANCE:BTCUSDT`) trade 24/7.
