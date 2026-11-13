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
| Testing | **flutter_test**, **mocktail** | Unit + widget tests, mocking services |

Minimum: Android 6.0 (API 23), iOS 13.

## 2. External data

See [API_SPEC.md](API_SPEC.md) for exact endpoints.

- **Finnhub REST** — symbol search, quote (current price, day stats), company profile
- **Finnhub WebSocket** — live trade ticks for subscribed symbols
- **Chart history** — Finnhub's candle endpoint is not on the free plan. v1.0 chart uses:
  1. **Intraday "live" chart** built from ticks collected while the screen is open, seeded with the quote's open/high/low/prev-close, and
  2. *(optional, F4b)* daily history from **Twelve Data** free tier `/time_series` if time allows.

## 3. Data models

All money is stored as **integer cents** (`int`) to avoid floating-point errors.
Prices from the API (`double`) are converted with `(price * 100).round()`.

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
  final int quantity;          // whole shares
  final int avgCostCents;      // average cost per share
}

enum TradeSide { buy, sell }

class Trade {
  final String id;             // uuid / timestamp-based
  final String symbol;
  final TradeSide side;
  final int quantity;
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

### Buy
- Preconditions: `quantity >= 1`, price known, `quantity * price <= cash`
- `cash -= quantity * price`
- If holding exists:
  `newAvg = ((oldQty * oldAvg) + (qty * price)) / (oldQty + qty)` (rounded to nearest cent)
  `qty = oldQty + qty`
- Else create holding with `avg = price`
- Append Trade(side: buy)

### Sell
- Preconditions: `quantity >= 1`, holding exists, `quantity <= holding.quantity`, price known
- `cash += quantity * price`
- `realizedPnl = (price - avgCost) * quantity`
- `holding.quantity -= quantity`; remove holding if 0 (avg cost unchanged on sell)
- Append Trade(side: sell, realizedPnl)

### Derived values (computed, never stored)
- `marketValue(holding) = qty * livePrice`
- `unrealizedPnl(holding) = (livePrice - avgCost) * qty`
- `unrealizedPnl% = (livePrice - avgCost) / avgCost * 100`
- `portfolioValue = cash + Σ marketValue`
- `totalReturn = portfolioValue - 10_000_000` (and %)

### Errors (typed, not strings)
`InsufficientFunds`, `InsufficientShares`, `InvalidQuantity`, `PriceUnavailable`

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

- API key passed at build time: `--dart-define=FINNHUB_API_KEY=...` read via `String.fromEnvironment`.
- Never hardcode keys. See [SECURITY.md](SECURITY.md).

## 8. Non-functional

- Null-safe Dart, `flutter analyze` with zero warnings.
- All user-facing amounts formatted as `$1,234.56`; percentages to 2 decimals with sign (`+1.25%`).
- Accessibility: min tap target 48dp, semantic labels on icons, gains/losses not shown by color alone (use +/− and arrows).
