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
│ [ Live ] [ 1M ]                 │  ← range chips (1M only if F4b done)
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

### 3.4 Order Sheet (bottom sheet)
```
┌─────────────────────────────────┐
│ Buy AAPL                        │
│ Market price        $189.42     │
│ Quantity      [ −  ] 5 [ + ]    │
│ ─────────────────────────────── │
│ Estimated cost      $947.10     │
│ Cash available   $100,000.00    │
│ Cash after        $99,052.90    │
│                                 │
│ [       Confirm Buy        ]    │
└─────────────────────────────────┘
```
- Numeric keyboard; stepper −/+; **Max** chip (max affordable for buy / owned for sell).
- Inline validation under quantity ("Not enough cash", "You own only 3 shares").
- Confirm button disabled while invalid. Haptic feedback on success.
- Sell sheet also shows **Estimated realized P&L**.

### 3.5 Portfolio
- Header card: **Total value** (display), Cash, Invested, **Total return** $ and %.
- Holdings list: symbol, `5 sh · avg $185.00`, live price, P&L $/% on right.
- Optional: simple allocation bar (percent of value per holding).
- Empty state: "No holdings yet — buy your first stock" → button to Watchlist.

### 3.6 History
- Grouped by day. Row: `BUY` (blue badge) / `SELL` (orange badge), `5 AAPL @ $189.42`, time, realized P&L for sells.

### 3.7 Settings
- Reset account (destructive, red, confirmation dialog)
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
