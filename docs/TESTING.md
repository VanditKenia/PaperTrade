# Testing

## 1. Strategy

| Layer | Test type | Tool | Priority |
|---|---|---|---|
| PortfolioEngine (domain) | Unit | flutter_test | **Must** — this is where money bugs live |
| Money formatting | Unit | flutter_test | Must |
| Throttle utility | Unit (fake time) | flutter_test + fake_async | Should |
| WebSocket message parsing | Unit | flutter_test | Should |
| Order sheet validation | Widget | flutter_test | Should |
| Full flows | Manual QA | device/emulator | Must before submission |

Run: `flutter test` · Coverage: `flutter test --coverage`

## 2. Required unit tests — PortfolioEngine

```
buy
  ✓ deducts cost from cash and creates holding with avg = price
  ✓ buying more of an existing holding updates weighted average cost
  ✓ throws InsufficientFunds when cost > cash (state unchanged)
  ✓ throws InvalidQuantity for qty 0 or negative
  ✓ throws PriceUnavailable when price is null/<=0
  ✓ appends a BUY trade with correct fields

sell
  ✓ adds proceeds to cash and reduces quantity
  ✓ computes realized P&L = (price - avg) * qty
  ✓ selling all shares removes the holding
  ✓ avg cost is unchanged after a partial sell
  ✓ throws InsufficientShares when qty > owned
  ✓ throws InsufficientShares when no holding exists

summary
  ✓ portfolio value = cash + Σ qty * livePrice
  ✓ unrealized P&L and % correct for gain and loss
  ✓ total return vs $100,000 start

reset
  ✓ returns cash 10_000_000, no holdings, no trades

fractional (quantities in units of 1/10,000 share)
  ✓ buy 0.5 share: cost rounds half up, basis = cost
  ✓ order worth less than half a cent → OrderTooSmall
  ✓ minimum quantity 0.0001 works when it is worth a cent
  ✓ partial sells take a proportional basis; avg cost unchanged
  ✓ selling everything realizes the exact total P&L
  ✓ cash + basis − realized always equals the starting cash
  ✓ realizedPnl (order preview) matches what sell records
  ✓ summary uses exact cost for market value and P&L

orders (limit & stop-loss)
  ✓ limit buy reserves cash at the limit; cash itself is untouched
  ✓ sell orders reserve quantity
  ✓ reserved cash / shares cannot be spent twice (partial availability)
  ✓ cancel releases the reservation; unknown id → OrderNotFound
  ✓ limit buy fills at the tick price, below the limit
  ✓ limit sell and stop-loss fill with realized P&L
  ✓ a fill can use its own reserved cash
  ✓ fill rejects a price that doesn't meet the condition
  ✓ validation: quantity, price, value, ownership, type
  ✓ input state is never changed; reset clears orders
```

`performance_calculator_test` (one group per metric): empty/buys-only; total realized P&L sums sells only; trade count = buys + sells; win rate incl. break-even and 0%/100%; average win and loss (half-up rounding, null when none); best/worst incl. single sell, ties (earliest) and never a buy.

`value_history_test`: due only after 5 minutes; append keeps input unchanged; cap at 2,000 drops the oldest.

`alert_rules_test`: crossing up/down incl. exactly at the target; no fire while staying past the target; first price since opening fires only if past; fire once (triggered alerts skipped); unchanged price isn't a tick; other symbols ignored; several alerts on one tick; `targetError` rules.

`order_matcher_test`: trigger rules incl. boundaries (≤ / ≥ at exactly the limit/stop), only limit buys reserve cash, ticks = changed prices only, triggered orders oldest first with their tick price.

Example worked case (use as a test):
1. Start cash $100,000.00
2. Buy 10 AAPL @ $100.00 → cash $99,000.00, holding 10 @ avg $100.00
3. Buy 10 AAPL @ $110.00 → cash $97,900.00, holding 20 @ avg $105.00
4. Sell 5 AAPL @ $120.00 → cash $98,500.00, holding 15 @ avg $105.00, realized P&L +$75.00
5. Live price $100.00 → unrealized P&L = (100 − 105) × 15 = −$75.00, portfolio value = $98,500 + $1,500 = $100,000.00

## 3. Other unit tests

- `money_test`: `formatCents(123456) == "$1,234.56"`, negative values, `toCents(189.425)` rounding; `formatShares` (4 decimals, trailing zeros trimmed); `parseShares` / `parseDollars` (exact, reject junk and extra decimals).
- `quantity_test`: `costCents` rounds half up (0.5¢ → 1¢, 0.4999¢ → 0¢) and doesn't overflow; `maxAffordableUnits` is the largest quantity whose cost fits; `unitsForAmount` never costs more than the amount.
- `portfolio_repository_test`: migration of old whole-share data (qty × 10,000, basis = qty × avg, trades too, not migrated twice); new-format load rejects non-whole units and negative basis.
- `portfolio_repository_test`: open orders and fill types round-trip; old trades load as market; corrupt orders skipped.
- `order_matcher_provider_test` (fake ticks): limit buy fills at the triggering tick, not before; stop-loss fills; an unchanged price doesn't fill (no stale fills); cancelled orders never fill; one fill per order while a save is in flight; a fill and a user trade at the same time both survive; an unfillable order is cancelled.
- `value_history_repository_test`: round trip; bad entries skipped; whole-number doubles accepted (web).
- `stats_provider_test` (fake time): records on open, every 5 minutes and not more often, on every trade with the value after it; reset clears and restarts from the new balance; placing an order records nothing; stats follow trades.
- `alert_repository_test`: waiting + triggered alerts round-trip; corrupt entries skipped.
- `alert_monitor_provider_test` (fake ticks, fake notifications): fires on crossing, marks triggered, persists, notifies, pushes the snackbar event; fires once even if the price crosses again; no fire while already past; deleted alerts never fire; a failed save can't cause a second fire.
- `throttle_test`: 20 ticks in 400 ms → 1 emission with latest values; ticks across 1.2 s → ~3 emissions.
- `ws_parse_test`: valid trade message → ticks; ping ignored; malformed JSON doesn't throw; multi-trade message keeps latest per symbol.

## 4. Widget tests

- Order sheet: entering qty that exceeds cash disables Confirm and shows "Not enough cash".
- Order sheet: Max button fills max affordable quantity (527.9273 for $100,000 at $189.42), also from Amount mode.
- Order sheet: decimal input (≤ 4 decimals), minimum 0.0001; Amount ($) mode converts $500 → 2.6396 shares and buys that; fractional sell Max and realized P&L.
- Watchlist empty state renders "Search stocks" button.
- Order sheet: Limit buy pre-fills the price, shows the app-open note and Cash reserved, places the order; empty price blocks it; Max uses unreserved cash; Stop-loss sell respects shares in open orders.
- Portfolio: Open orders section lists orders with the note and cancels; hidden when empty.
- History: fill type (Market / Limit / Stop-loss) on each row.
- Alerts: sheet pre-fill + validation per direction + create (saves, asks permission, confirms) + failed save; list filtered per stock with status and delete; Settings list with symbols; empty state; AppShell snackbar when an alert fires.
- Stats: empty states (no trades / no sells / chart < 2 points), every metric rendered, chart shown; Portfolio's Stats button opens it.

## 5. Manual QA checklist (before submitting)

- [ ] Fresh install shows $100,000 and default watchlist
- [ ] Search "tesla" → TSLA appears → add to watchlist
- [ ] Prices update live (test with BINANCE:BTCUSDT if US market closed)
- [ ] Buy 5 shares → cash decreases correctly, holding appears
- [ ] Buy more → avg cost updates correctly
- [ ] Buy 0.5 share and $50 worth (Amount mode) → fractional holding shown with up to 4 decimals
- [ ] Sell all of a fractional holding → holding removed, cash exact
- [ ] Try buying more than cash → blocked with message
- [ ] Sell part → realized P&L shown, holding reduced
- [ ] Sell all → holding removed
- [ ] Place a limit buy just above the price → fills on the next tick, History says "Limit"
- [ ] Place a stop-loss below the price → listed under Open orders with reserved shares; Cancel removes it
- [ ] With an open sell order, the order sheet only offers the unreserved shares
- [ ] Kill and reopen app → everything persisted (including open orders)
- [ ] BTC detail → alert just above the price → snackbar when it crosses (Android: notification too, after allowing the permission); it shows "Triggered" and doesn't fire again; delete it in Settings
- [ ] Portfolio → Stats: numbers match History; chart gains a point per trade and every 5 min; survives restart; Reset clears it
- [ ] Airplane mode → offline banner, trading disabled, no crash
- [ ] Turn network back on → reconnects and prices resume
- [ ] Reset account → back to $100,000, history cleared
- [ ] Rotate / small screen — no overflow errors
