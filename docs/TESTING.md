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
```

Example worked case (use as a test):
1. Start cash $100,000.00
2. Buy 10 AAPL @ $100.00 → cash $99,000.00, holding 10 @ avg $100.00
3. Buy 10 AAPL @ $110.00 → cash $97,900.00, holding 20 @ avg $105.00
4. Sell 5 AAPL @ $120.00 → cash $98,500.00, holding 15 @ avg $105.00, realized P&L +$75.00
5. Live price $100.00 → unrealized P&L = (100 − 105) × 15 = −$75.00, portfolio value = $98,500 + $1,500 = $100,000.00

## 3. Other unit tests

- `money_test`: `formatCents(123456) == "$1,234.56"`, negative values, `toCents(189.425)` rounding.
- `throttle_test`: 20 ticks in 400 ms → 1 emission with latest values; ticks across 1.2 s → ~3 emissions.
- `ws_parse_test`: valid trade message → ticks; ping ignored; malformed JSON doesn't throw; multi-trade message keeps latest per symbol.

## 4. Widget tests

- Order sheet: entering qty that exceeds cash disables Confirm and shows "Not enough cash".
- Order sheet: Max button fills max affordable quantity.
- Watchlist empty state renders "Search stocks" button.

## 5. Manual QA checklist (before submitting)

- [ ] Fresh install shows $100,000 and default watchlist
- [ ] Search "tesla" → TSLA appears → add to watchlist
- [ ] Prices update live (test with BINANCE:BTCUSDT if US market closed)
- [ ] Buy 5 shares → cash decreases correctly, holding appears
- [ ] Buy more → avg cost updates correctly
- [ ] Try buying more than cash → blocked with message
- [ ] Sell part → realized P&L shown, holding reduced
- [ ] Sell all → holding removed
- [ ] Kill and reopen app → everything persisted
- [ ] Airplane mode → offline banner, trading disabled, no crash
- [ ] Turn network back on → reconnects and prices resume
- [ ] Reset account → back to $100,000, history cleared
- [ ] Rotate / small screen — no overflow errors
