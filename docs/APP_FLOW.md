# App Flow

## 1. Navigation map

```
                 ┌──────────────────── Bottom Navigation ─────────────────────┐
                 │                         │                    │             │
            [Watchlist]               [Portfolio]          [History]     [Settings]
                 │                         │
         (search icon)               (tap holding)
                 ▼                         │
             [Search] ──tap result──▶ [Stock Detail] ◀──────────┘
                                          │
                                   [Buy] / [Sell]
                                          ▼
                                  [Order Sheet] (bottom sheet)
                                          │ confirm
                                          ▼
                          success toast → back to Stock Detail
```

Bottom nav tabs: **Watchlist · Portfolio · History · Settings**

## 2. First launch

1. App opens → Hive initializes → no saved data found.
2. Create wallet with **$100,000.00** virtual cash.
3. Seed watchlist with defaults: `AAPL, MSFT, GOOGL, AMZN, TSLA, BINANCE:BTCUSDT` (BTC so live ticks work 24/7).
4. Show one-time banner on Watchlist: *"You have $100,000 virtual cash. Prices are real, money is not. Tap any stock to start trading."*
5. WebSocket connects and subscribes to watchlist symbols.

## 3. Returning launch

1. Load watchlist, wallet, holdings, trades from Hive (instant).
2. Show cached prices immediately, marked stale.
3. Fetch fresh quotes (REST) + connect WebSocket → prices go live.

## 4. User journeys

### J1 — Find and watch a stock
1. Watchlist → tap 🔍
2. Type "nvidia" (search fires 400 ms after typing stops)
3. Results list: `NVDA — NVIDIA Corp` with ☆
4. Tap ☆ → added to watchlist (☆ becomes ★), WebSocket subscribes NVDA
5. Back → NVDA appears in watchlist with live price

### J2 — Buy a stock
1. Watchlist → tap AAPL → Stock Detail
2. See live price, change, chart, day stats, "You own: 0 shares"
3. Tap **Buy** → Order Sheet opens
4. Enter quantity `5` → sheet shows: price × 5 = estimated cost, cash after
5. If cost > cash → **Buy** button disabled, message "Not enough cash"
6. Tap **Confirm Buy** → trade executes at latest price
7. Toast: "Bought 5 AAPL @ $189.42" → sheet closes → "You own: 5 shares"

### J3 — Track performance
1. Portfolio tab → header: **Total value**, **Cash**, **Total return** (+/−, %)
2. Holdings list: symbol, qty, avg cost, live price, P&L ($ and %), colored + arrow
3. Values update live as prices move

### J4 — Sell a stock
1. Portfolio → tap AAPL → Stock Detail → **Sell**
2. Order Sheet shows max sellable (5) and a **Max** button
3. Enter `2` → shows proceeds and realized P&L preview
4. Confirm → toast "Sold 2 AAPL @ $191.10 · P&L +$3.36"
5. Holding updates to 3 shares; selling all removes it from Portfolio

### J5 — Review trades
History tab → reverse-chronological list: BUY/SELL badge, symbol, qty @ price, time, realized P&L for sells. Empty state: "No trades yet."

### J6 — Reset account
Settings → **Reset account** → confirm dialog ("This deletes all holdings and trades and resets cash to $100,000") → reset → back to Watchlist.

## 5. Edge flows

| Situation | Behavior |
|---|---|
| No internet | Banner "Offline — showing last prices". Buy/Sell disabled. |
| WebSocket drops | Auto-reconnect silently; small "Reconnecting…" indicator if > 5 s |
| Market closed | Detail shows "Market closed · last price". Trading allowed at last price (labelled) |
| Price unknown (new symbol, no quote yet) | Buy/Sell disabled with "Waiting for price…" |
| Search returns nothing | "No results for 'xyz'" |
| API rate limit hit (HTTP 429) | Show "Too many requests, try again shortly"; back off 60 s |
| Remove watchlist item | Swipe left → remove → unsubscribe from WS (unless it's a holding) |
