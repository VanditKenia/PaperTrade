# TRD — Technical Requirements Document

## 1. Tech stack

| Concern | Choice | Why |
|---|---|---|
| Framework | **Flutter 3.x / Dart 3** | One codebase for Android + iOS; declarative UI (same model as SwiftUI) |
| State management | **flutter_riverpod** | Testable, compile-safe, clear separation of state from UI (MVVM-like) |
| Local storage | **hive_ce** + **hive_ce_flutter** | Fast, offline, no native setup; community-maintained fork of Hive |
| REST | **http** | Simple, enough for our needs |
| Real-time | **web_socket_channel** | Standard WebSocket client for Finnhub stream |
| Charts | **fl_chart** | Lightweight, customizable line charts |
| Formatting | **intl** | Currency and number formatting |
| Notifications | **flutter_local_notifications** | Price-alert notifications on Android (no backend); `flutter_web_plugins` is needed because the plugin ships a web implementation |
| Testing | **flutter_test**, **mocktail** | Unit + widget tests, mocking services |

Minimum: Android 6.0 (API 23), iOS 13.

## 2. External data

See [API_SPEC.md](API_SPEC.md) for exact endpoints.

- **Finnhub REST** — symbol search, quote (current price, day stats), company profile
- **Finnhub WebSocket** — live trade ticks for subscribed symbols
- **Twelve Data REST** — chart history (`/time_series`) for 1D · 1W · 1M · 6M · 1Y. Finnhub's candle endpoint is not on the free plan. Cached in memory (1D 5 min, others 1 h) and capped at 8 requests/min. Optional: if the proxy has no `TWELVE_DATA_API_KEY` secret the chart shows "History unavailable".
- **Live ticks on the chart** — the 1D line is extended with WebSocket ticks collected while the detail screen is open (also the only chart when history is unavailable).

## 3. Data models

All money is stored as **integer cents** (`int`) to avoid floating-point errors.
Prices from the API (`double`) are converted with `(price * 100).round()`.

All quantities are stored as **integer units of 1/10,000 share** (4 decimal places), `unitsPerShare = 10000` in `domain/quantity.dart`: 1.5 shares = `15000`, the minimum 0.0001 share = `1`.

```dart
class Stock {           // search result / watchlist item
  final String symbol;  // "AAPL"
  final String name;    // "Apple Inc"
}

class Quote {
  final String symbol;
  final int currentCents;     // c
  final int changeCents;      // d
  final double changePercent; // dp
  final int highCents, lowCents, openCents, prevCloseCents; // h, l, o, pc
  final DateTime timestamp;
}

class PriceTick {       // from WebSocket
  final String symbol;
  final int priceCents;
  final DateTime time;
}

class Holding {
  final String symbol;
  final int quantity;          // units of 1/10,000 share
  final int costBasisCents;    // total paid for the shares still held
  int get avgCostCents;        // costBasis × 10,000 / quantity, half up (display only)
}

enum TradeSide { buy, sell }

class Trade {
  final String id;             // uuid / timestamp-based
  final String symbol;
  final TradeSide side;
  final int quantity;          // units of 1/10,000 share
  final int priceCents;        // fill price per share
  final DateTime executedAt;
  final int? realizedPnlCents; // only for sells
}

class Wallet {
  final int cashCents;         // starts at 10_000_000 ($100,000.00)
}
```

## 4. Business rules (Portfolio Engine)

Implemented as **pure Dart** in `domain/portfolio_engine.dart` — no Flutter imports, fully unit tested.

### Cost rule (the only quantity × price)
`cost(units, price) = units × price / 10,000`, rounded **half up** to a whole cent (`costCents` in `domain/quantity.dart`, computed with `BigInt` so it can't overflow). Cash moves, cost basis, market value and the order sheet preview all use it, so they always agree.
Example: 0.5 share × $189.43 = $94.715 → **$94.72**.

### Buy
- Preconditions: `quantity >= 1` unit, price known, `cost >= 1` cent (else `OrderTooSmall`), `cost <= cash`
- `cash -= cost`
- `holding.quantity += quantity`; `holding.costBasis += cost` (new holding: basis = cost)
- Weighted average cost = `costBasis / quantity`: derived, never stored, so it stays exact.
- Append Trade(side: buy)

### Sell
- Preconditions: `quantity >= 1` unit, holding exists, `quantity <= holding.quantity`, price known, `proceeds >= 1` cent (else `OrderTooSmall`)
- `proceeds = cost(quantity, price)`; `cash += proceeds`
- `soldBasis = costBasis × quantity / holding.quantity` (half up); selling everything takes the whole basis, so no cents are left behind
- `realizedPnl = proceeds − soldBasis`
- `holding.quantity -= quantity`, `holding.costBasis -= soldBasis`; remove holding if 0. Avg cost is unchanged by a sell (up to the half-cent rounding of the split).
- Append Trade(side: sell, realizedPnl)
- Invariant (tested): `cash + Σ costBasis − Σ realizedPnl = startingCash`, to the cent.

### Saved data / migration
- The saved map carries `v: 2`. Holdings save `qty` (units) and `basis`.
- Data without `v: 2` is from before fractional quantities: holding and trade `qty` × 10,000, `basis = qty × avg`. It is rewritten in the new format on the next save.

### Max quantity
- Buy: largest `units` with `cost(units, price) <= cash` = `((2 × cash + 1) × 5,000 − 1) ~/ price`.
- Sell: the units owned.
- Dollar amount → units: `amount × 10,000 ~/ price` (rounded down, so the cost never exceeds the amount).

### Pending orders (limit & stop-loss)
- `PendingOrder { id, symbol, side, type (limit | stopLoss), quantity, triggerPriceCents, createdAt }`, stored in `PortfolioState.orders`. Trades record `orderType` (market | limit | stopLoss): how they filled.
- Valid combinations: limit buy, limit sell, stop-loss sell. Anything else is a programming error (`ArgumentError`).
- Trigger rules (`PendingOrder.triggersAt`): limit buy `price <= limit` · limit sell `price >= limit` · stop-loss `price <= stop`.
- **Reservations** (derived from open orders, never stored):
  - `reservedCash = Σ cost(qty, limit)` over limit buys; `availableCash = cash − reservedCash`. Wallet cash still includes reserved cash (not spent until it fills), so portfolio value is unchanged.
  - `availableQuantity(symbol) = held − Σ qty` of open sell orders for it.
- `placeOrder`: `quantity >= 1`, trigger price > 0 (else `InvalidOrderPrice`), `cost(qty, trigger) >= 1` cent; limit buy needs `cost(qty, limit) <= availableCash`, sells need `qty <= availableQuantity`.
- Market `buy` / `sell` check **available** cash / quantity, so nothing is spent twice.
- `cancelOrder(id)`: removes it (releases the reservation); unknown id → `OrderNotFound`.
- `fillOrder(id, price)`: the price must meet the trigger (`OrderNotTriggered`). The order is removed first, then the trade runs through the market buy/sell rules at the **tick price** with `orderType` set. A limit buy fills at ≤ limit, so its cost ≤ what it reserved.
- Matching (`OrderMatcher`, pure): ticks = symbols whose price changed between two live snapshots (an unchanged price is not a tick, so nothing fills at a stale price); triggered = open orders whose symbol ticked and whose rule holds, oldest first, each filling at its tick price.
- `orderMatcherProvider` listens to `livePricesProvider` and calls `portfolioProvider.notifier.fillOrder(id, priceCents:)`; one fill in flight per order. An order that can no longer fill (e.g. now worth 0¢) is cancelled. A failed save leaves it open for the next tick.
- The portfolio notifier runs changes one at a time, so a fill and a user trade can't overwrite each other.
- Orders only fill **while the app is open** (no backend).
- Persistence: `orders` list in the same atomic Hive value; trades gain `type`. Older data has neither → no orders, trades = market. Invalid saved orders are skipped.

### Starting balance / reset
- `PortfolioState.startingCashCents` is stored with the rest of the state (same atomic Hive value, key `start`). Saved data without it loads as `10_000_000` ($100,000) — the only hard-coded amount (`defaultStartingCashCents`).
- `reset(startingCashCents)`: cash = starting cash, no holdings, no trades, no open orders.
- Valid starting cash: whole dollars (`cents % 100 == 0`), `10_000` ≤ cents ≤ `1_000_000_000` ($100 – $10,000,000). Otherwise `InvalidStartingBalance`.

### Derived values (computed, never stored)
- `marketValue(holding) = cost(qty, livePrice)`
- `unrealizedPnl(holding) = marketValue − costBasis`
- `unrealizedPnl% = unrealizedPnl / costBasis * 100` (0 if the basis rounded to 0)
- `portfolioValue = cash + Σ marketValue`
- `totalReturn = portfolioValue - startingCashCents` (and % of `startingCashCents`)

### Errors (typed, not strings)
`InsufficientFunds`, `InsufficientShares`, `InvalidQuantity`, `PriceUnavailable`, `OrderTooSmall`, `InvalidOrderPrice`, `OrderNotFound`, `OrderNotTriggered` (trade errors) · `InvalidStartingBalance` (reset)

## 5. Performance requirements

| Requirement | Target |
|---|---|
| Live tick → UI | ≤ 1 s |
| UI rebuild rate | **Throttled to max 2 updates/sec per screen** (ticks buffered, latest price per symbol wins) |
| Scrolling | 60 fps on watchlist with 30+ symbols |
| Cold start | < 2 s to watchlist (from local cache) |
| REST rate limit | Stay under 60 calls/min — debounce search (400 ms), cache quotes (30 s) |

## 6. Connectivity & resilience

- WebSocket **auto-reconnect** with exponential backoff (1s, 2s, 4s … max 30s); re-subscribe all symbols after reconnect.
- On app background → close socket; on resume → reconnect.
- Offline → show last cached prices with a "Offline · last updated HH:MM" banner. Trading disabled while price is unknown.
- Max 50 subscribed symbols (Finnhub free limit).

## 7. Configuration

- No API key in the app (Step 14): `--dart-define=PROXY_BASE_URL=https://…workers.dev` read via `String.fromEnvironment`; keys are Cloudflare Worker secrets (`proxy/`).
- Never hardcode keys. See [SECURITY.md](SECURITY.md).

## 8. Non-functional

- Null-safe Dart, `flutter analyze` with zero warnings.
- All user-facing amounts formatted as `$1,234.56`; percentages to 2 decimals with sign (`+1.25%`).
- Accessibility: min tap target 48dp, semantic labels on icons, gains/losses not shown by color alone (use +/− and arrows).
