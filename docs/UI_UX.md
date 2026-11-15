# UI / UX Specification

## 1. Design principles

1. **Numbers first** — prices and P&L are the hero; everything else is secondary.
2. **Glanceable** — user should understand gain/loss in under a second.
3. **Calm under motion** — live updates should not make the screen jumpy.
4. **Safe actions** — every trade shows a clear preview before confirming.

## 2. Design system

### Colors (dark theme default — standard for trading apps)

| Token | Hex | Use |
|---|---|---|
| `bg` | `#0E1117` | App background |
| `surface` | `#161B22` | Cards, sheets |
| `surfaceAlt` | `#21262D` | Input fields, dividers |
| `textPrimary` | `#E6EDF3` | Main text, prices |
| `textSecondary` | `#8B949E` | Labels, metadata |
| `gain` | `#22C55E` | Positive change |
| `loss` | `#EF4444` | Negative change |
| `accent` | `#3B82F6` | Buttons, links, selection |
| `warning` | `#F59E0B` | Offline / market closed |

**Never rely on color alone:** always pair with `+`/`−` sign and ▲/▼ arrow.

### Typography (Material 3, default font or Inter)

| Style | Size / weight | Use |
|---|---|---|
| `display` | 32 / bold | Big price on Stock Detail, portfolio total |
| `title` | 20 / semibold | Screen titles |
| `body` | 16 / regular | List primary text |
| `label` | 13 / medium | Secondary info, chips |
| **Numbers** | `FontFeature.tabularFigures()` | All prices — digits have equal width so values don't "jiggle" when updating |

### Spacing & shape
4-pt grid (4, 8, 12, 16, 24, 32). Card radius 12. Bottom sheet radius 20. Min tap target 48dp.

## 3. Screens

### 3.1 Watchlist
```
┌─────────────────────────────────┐
│ Watchlist                    🔍 │
│ ● Live      Market open         │  ← status chip
├─────────────────────────────────┤
│ AAPL                 $189.42    │
│ Apple Inc       ▲ +1.25 (+0.66%)│  ← green
├─────────────────────────────────┤
│ TSLA                 $242.10    │
│ Tesla Inc       ▼ −3.40 (−1.38%)│  ← red
└─────────────────────────────────┘
```
- Price **flashes** briefly (300 ms background tint green/red) when it ticks up/down.
- Swipe left to remove. Pull to refresh quotes.
- Empty state: illustration + "Your watchlist is empty" + **Search stocks** button.

### 3.2 Search
- Autofocused text field, debounced 400 ms.
- Result row: symbol (bold), company name, ☆/★ toggle; tap row → Stock Detail.
- States: idle hint ("Search by name or symbol"), loading (shimmer rows), empty, error with Retry.

### 3.3 Stock Detail
```
┌─────────────────────────────────┐
│ ←  AAPL                      ★  │
│ Apple Inc                       │
│ $189.42                         │  ← display style
│ ▲ +1.25 (+0.66%) today          │
│ ┌─────────────────────────────┐ │
│ │        line chart           │ │  ← green if up on day, red if down
│ └─────────────────────────────┘ │
│ [1D] [1W] [1M] [6M] [1Y]        │  ← range chips, default 1D
│ Open 188.10   High 190.02       │
│ Low  187.55   Prev close 188.17 │
│ ─────────────────────────────── │
│ Your position: 5 shares         │
│ Avg cost $185.00 · P&L +$22.10  │
├─────────────────────────────────┤
│ [   SELL   ]     [    BUY    ]  │  ← sticky bottom bar
└─────────────────────────────────┘
```
- Sell button hidden/disabled if user owns 0 shares.
- Chart (Step 8): straight segments, y-axis fitted to the data, green if the range's last price ≥ its first, red otherwise. The change line under the price shows the change for the selected range ("today", "past week", …). 1D keeps extending with live ticks.
- Touch / drag shows a crosshair with price and date/time (time for 1D/1W, date for longer ranges).
- States: loading skeleton; error + Retry; "No chart data for this range"; no Twelve Data key → "History unavailable" with live ticks still drawn.
- **Price alerts** section under the position: title + "Add alert" button (opens §3.3b), the note "Alerts only work while the app is open.", then this stock's alerts, newest first: bell icon + "Rises above $200.00", subtitle "Waiting" or "Triggered Nov 15 2:30 PM at $200.10" (check icon), 🗑 delete (tooltip "Delete alert"). Empty: "No price alerts".

### 3.3b Price alert sheet (bottom sheet)
```
┌─────────────────────────────────┐
│ Alert for AAPL                  │
│ Current price $189.42           │
│ [ Rises above | Falls below ]   │
│ Price  $[ 200.00          ]     │
│ Fires once. Alerts only work    │
│ while the app is open.          │
│ [        Create alert       ]   │
└─────────────────────────────────┘
```
- Price pre-filled with the current price; `$`, up to 2 decimals (same input rule as other dollar fields).
- Validation: empty/0 → "Enter a price"; Rises above needs a target above the current price, Falls below one below it ("Must be above/below the current price"). **Create alert** disabled while invalid.
- On create: saved, snackbar "Alert created"; on Android the first time, the system notification permission prompt. Denying it is fine: the in-app snackbar still works.
- When an alert fires (app open): floating snackbar "AAPL rose above $200.00 · now $200.15" on any screen, plus an Android notification with the same text.

### 3.4 Order Sheet (bottom sheet)
```
┌─────────────────────────────────┐
│ Buy AAPL                        │
│ Market price        $189.42     │
│ [ Quantity | Amount ($) ]       │
│ Quantity  [ − ] 2.5 [ + ] [Max] │
│ ─────────────────────────────── │
│ Estimated cost      $947.10     │
│ Cash available   $100,000.00    │
│ Cash after        $99,052.90    │
│                                 │
│ [       Confirm Buy        ]    │
└─────────────────────────────────┘
```
- Decimal keyboard. **Quantity** mode: up to 7 digits + 4 decimals, minimum 0.0001; stepper −/+ moves one whole share.
- **Amount ($)** mode: up to 9 digits + 2 decimals; converts to the largest quantity that costs no more than the amount and shows it as a "Quantity" row (e.g. $500 at $189.42 → 2.6396 shares). No steppers.
- Switching Amount → Quantity keeps the converted quantity; Quantity → Amount starts empty.
- **Max** chip fills the exact max: largest affordable quantity for buy (cost rounded half up still ≤ cash) / everything owned for sell. It switches to Quantity mode, so it is never off by the rounding of a dollar amount.
- The field rejects any edit that isn't a valid number (no minus, letters, second dot or extra decimals).
- Quantities display with up to 4 decimals, trailing zeros trimmed ("2.5 shares", "1 share", "0.0001 sh") everywhere: order sheet, position, holdings, history, snackbar.
- Inline validation under quantity ("Not enough cash", "You own only 2.5 shares", "Minimum quantity is 0.0001", "Order value must be at least $0.01").
- Confirm button disabled while invalid. Haptic feedback on success.
- Sell sheet also shows **Estimated realized P&L**.
- **Order type** selector above quantity: `Market | Limit` (buy), `Market | Limit | Stop-loss` (sell). For Limit/Stop-loss:
  - **Limit price** / **Stop price** field (`$`, up to 2 decimals), pre-filled with the current price; empty or 0 → "Enter a limit price" / "Enter a stop price".
  - One-line rule + note: "Buys when the price is at or below the limit. Orders only execute while the app is open."
  - Preview uses the limit/stop price: buy shows **Cash reserved**; sells show estimated proceeds and realized P&L at that price. Amount mode converts at that price.
  - Button: **Place Buy order** / **Place Sell order**; toast "Limit buy 5 AAPL @ $180.00 placed".
- "Cash available", Max and validation use cash/shares **not reserved** by open orders ("Only 2 shares available (rest in open orders)").
- The sheet scrolls on short screens.

### 3.5 Portfolio
- Header card: **Total value** (display), Cash, Invested, **Total return** $ and % (vs the starting balance), and "Starting balance $X".
- Holdings list: symbol, `5 sh · avg $185.00`, live price, P&L $/% on right.
- App bar: **Stats** icon (insights, tooltip "Stats") → Stats screen (§3.5b).
- **Open orders** section (only when there are any), between the header and holdings: note "Orders only execute while the app is open.", then one row per order: `Limit buy 5 AAPL @ $180.00`, "Reserves $900.00" (buy) / "Reserves 5 shares" (sell), ✕ button (tooltip "Cancel order") → snackbar "Order cancelled".
- Optional: simple allocation bar (percent of value per holding).
- Empty state: "No holdings yet — buy your first stock" → button to Watchlist.

### 3.5b Stats (from Portfolio)
```
┌─────────────────────────────────┐
│ ← Stats                         │
│ ┌ Portfolio value ────────────┐ │
│ │        ╱╲    ╱‾‾            │ │
│ │  ‾‾‾‾‾╱  ╲__╱               │ │
│ └─────────────────────────────┘ │
│ Realized P&L          +$200.00  │
│ Trades                       5  │
│ Win rate           66.7% (2/3)  │
│ Average win           +$125.00  │
│ Average loss           -$50.00  │
│ Best trade      +$150.00 · AAPL │
│ Worst trade      -$50.00 · MSFT │
└─────────────────────────────────┘
```
- Chart: portfolio value snapshots (PriceChart: green if the last value is above the first, red if below, grey if equal; crosshair shows value and "Nov 15, 2026 10:05 AM"). Fewer than 2 snapshots → "Not enough data yet — the chart fills in as you trade and keep the app open."
- Numbers in tabular figures; P&L values signed and colored; missing values show "—".
- Empty states: no trades → "No trades yet — stats appear after your first trade."; trades but no sells → "Win rate and P&L stats appear after your first sell."
- Offline banner like other screens (the data is local, so nothing else changes).

### 3.6 History
- Grouped by day. Row: `BUY` (blue badge) / `SELL` (orange badge), `5 AAPL @ $189.42`, `10:32 AM · Limit` (time · how it filled: Market / Limit / Stop-loss), realized P&L for sells.

### 3.6b Onboarding — starting balance (first launch only)
```
┌─────────────────────────────────┐
│ Choose your starting balance    │
│ Virtual money only. You can     │
│ change it later in Settings.    │
│                                 │
│ [$1K] [$10K] [$50K] [$100K] [$1M]│  ← chips; $100K selected by default
│ $ [ 100000            ]         │  ← digits only, whole dollars
│ Minimum is $100                 │  ← inline validation (red)
│                                 │
│ [       Start trading       ]   │  ← disabled while invalid
└─────────────────────────────────┘
```
- Chip tap fills the field; typing selects the matching chip (or none).
- Validation: empty → "Enter an amount"; < $100 → "Minimum is $100"; > $10,000,000 → "Maximum is $10,000,000".

### 3.7 Settings
- Reset account (destructive, red): dialog with the same presets + custom field as onboarding, pre-filled with the current starting balance; **Reset** disabled while invalid
- **Price alerts**: every alert, "AAPL · Rises above $200.00", status and delete (same list as §3.3), with the note "Alerts only work while the app is open."
- Data source note: "Market data by Finnhub. Prices may be delayed. Virtual money only."
- App version

## 4. States checklist (every data screen)

| State | Treatment |
|---|---|
| Loading | Skeleton/shimmer, not a blank screen |
| Empty | Friendly message + next action |
| Error | Short message + Retry button |
| Offline | Amber banner at top, last-known data shown |
| Stale price | Grey timestamp "as of 14:32" |

## 5. Micro-interactions

- Price flash on tick (300 ms).
- Number changes use `AnimatedSwitcher` with short fade.
- Successful trade: haptic + snackbar with summary.
- Bottom nav keeps each tab's scroll position.
