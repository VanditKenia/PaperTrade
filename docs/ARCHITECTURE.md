# Architecture

## 1. Overview

Layered, feature-first architecture. Dependencies point **inward only**:

```
UI (screens/widgets)
   │ watches
   ▼
Providers (Riverpod — state + view logic, like ViewModels in MVVM)
   │ calls
   ▼
Repositories (single source of truth; combine API + cache)
   │ uses
   ▼
Data sources (proxy REST client, proxy WebSocket, Hive local store)
   │ https / wss
   ▼
papertrade-proxy (Cloudflare Worker, proxy/) — holds the API keys
   │ adds keys server-side
   ▼
Finnhub REST + WebSocket · Twelve Data REST

Domain (models + PortfolioEngine) — pure Dart, used by all layers, depends on nothing
```

Rule: **UI never talks to APIs or Hive directly.** Domain never imports Flutter. **The app never talks to Finnhub or Twelve Data directly and holds no API key**; it only knows `PROXY_BASE_URL`.

### The proxy (proxy/)

```
App ──https──▶ Worker fetch handler
               │ Origin allowed? (localhost / ALLOWED_ORIGINS, else 403)
               │ per-IP rate limit (60/min, else 429)
               │ route + validate params (else 400 / 404)
               │ Cache API hit? → return
               ▼
               upstream fetch with key added → cache (if not an error) → return JSON

App ──wss /ws──▶ Worker ──▶ Relay Durable Object (one instance, idFromName("relay"))
                              │ SubscriptionBook: client → symbols, symbol → holder count
                              │ ONE upstream wss://ws.finnhub.io (key added here)
                              │ subscribes upstream to the union; unsubscribes when no holder
                              ▼
                 trade msgs filtered per client → each client socket
```

- Pure, unit-tested modules: `validate.ts`, `cors.ts`, `rate_limit.ts`, `subscriptions.ts`; `handler.ts` takes its fetch/cache/limiter as parameters so routing is tested with fakes.
- Why one Durable Object: a free Finnhub key allows very few WebSocket connections and 50 symbols; every app user shares one upstream socket.
- The relay drops the upstream socket when the last client leaves, so the object can sleep (free-plan duration limit).

## 2. Folder structure

```
lib/
  main.dart                     # init Hive, ProviderScope, run app
  app.dart                      # MaterialApp, theme, routes
  core/
    config.dart                 # API key from --dart-define, constants
    money.dart                  # cents <-> display formatting helpers
    theme.dart                  # colors, text styles
    throttle.dart               # stream throttling utility
  domain/
    models/                     # Stock, Quote, PriceTick, Holding, Trade, Wallet
    portfolio_engine.dart       # pure buy/sell/P&L logic
    trade_errors.dart           # typed errors
  data/
    finnhub_api.dart            # REST: search, quote, profile
    price_stream_service.dart   # WebSocket: subscribe, reconnect, tick stream
    local_store.dart            # Hive boxes: watchlist, wallet, holdings, trades
    market_repository.dart      # quotes + search + live prices (with caching)
    portfolio_repository.dart   # loads/saves portfolio, applies PortfolioEngine
  features/
    watchlist/
      watchlist_provider.dart
      watchlist_screen.dart
      widgets/price_tile.dart
    search/
      search_provider.dart
      search_screen.dart
    stock_detail/
      stock_detail_provider.dart
      stock_detail_screen.dart
      widgets/price_chart.dart
      widgets/order_sheet.dart
    portfolio/
      portfolio_provider.dart
      portfolio_screen.dart
      widgets/holding_tile.dart
    history/
      history_screen.dart
    settings/
      settings_screen.dart      # reset account, about
test/
  domain/portfolio_engine_test.dart
  core/money_test.dart
  core/throttle_test.dart
  data/price_stream_service_test.dart
  features/order_sheet_test.dart
proxy/                          # Cloudflare Worker (TypeScript) — Step 14
  wrangler.toml                 # Durable Object binding, ALLOWED_ORIGINS (no secrets)
  src/index.ts                  # entry: wires runtime cache/fetch into handle()
  src/handler.ts                # CORS check, rate limit, routing, cache, upstream fetch
  src/validate.ts               # route allowlist + param validation (pure)
  src/cors.ts · rate_limit.ts   # pure helpers
  src/subscriptions.ts          # SubscriptionBook: union of client symbols (pure)
  src/relay.ts                  # Durable Object: one upstream Finnhub WebSocket
  test/*.test.ts                # Vitest
```

## 3. Live price data flow (the most important flow)

```
Finnhub WS ──▶ proxy relay (/ws) ──trade msgs──▶ PriceStreamService
                               │ parse JSON → PriceTick
                               │ keep latest price per symbol in a Map
                               ▼
                         throttle (500 ms)
                               │ emit Map<String,int> snapshot
                               ▼
                     livePricesProvider (StreamProvider)
                         │                     │
                         ▼                     ▼
              WatchlistScreen           PortfolioScreen / StockDetail
              (only tiles whose          (P&L recomputed from
               price changed rebuild)     PortfolioEngine)
```

**Why throttle:** busy stocks can send dozens of trades per second. Rebuilding the UI on every tick wastes CPU and battery. We buffer ticks and push at most one snapshot every 500 ms — the user sees smooth, effectively real-time prices.

**Why per-tile rebuilds:** each `PriceTile` uses `ref.watch(livePricesProvider.select((m) => m[symbol]))`, so only tiles whose price changed rebuild.

## 4. Trade flow

```
OrderSheet (qty input) ──▶ portfolioProvider.buy(symbol, qty)
                               │ reads latest price
                               ▼
                         PortfolioEngine.buy(state, symbol, qty, price)
                               │ returns new state OR throws typed error
                               ▼
                         PortfolioRepository.save(newState)  → Hive
                               │
                               ▼
                         provider emits new state → UI updates, success toast
```

PortfolioEngine is **immutable**: takes a state, returns a new state. This makes it trivial to test and impossible to half-apply a trade.

## 5. State management (Riverpod)

| Provider | Type | Holds |
|---|---|---|
| `finnhubApiProvider` | Provider | REST client |
| `priceStreamServiceProvider` | Provider | WebSocket service (disposed on app close) |
| `livePricesProvider` | StreamProvider<Map<String,int>> | latest price per symbol |
| `watchlistProvider` | NotifierProvider<List<Stock>> | watchlist symbols; subscribes them to WS |
| `searchProvider` | AsyncNotifierProvider | debounced search results |
| `quoteProvider(symbol)` | FutureProvider.family | day stats for a symbol |
| `portfolioProvider` | NotifierProvider<PortfolioState> | wallet, holdings, trades; buy/sell/reset |
| `portfolioSummaryProvider` | Provider | derived: total value, P&L (recomputes on price change) |

## 6. Key design decisions

| Decision | Reason |
|---|---|
| Money as integer cents | Floats cause rounding bugs (`0.1 + 0.2 != 0.3`). Financial apps never use float for money. |
| Pure-Dart PortfolioEngine | Business logic testable without Flutter; easy to reason about |
| Throttled stream | Smooth UI under high tick volume |
| Repository layer | Swap data source (e.g. add NSE provider) without touching UI |
| Local-only storage | No user data leaves the device, works offline |
| API key proxy (Cloudflare Worker) | Keys never ship in the app or browser; one shared upstream socket and an edge cache stretch free-tier quotas; free plan, no server to run |
| Riverpod over setState | Shared state across screens (portfolio is used by 3 screens), testable |

## 7. iOS mapping (for interviews)

| Flutter (this app) | iOS native equivalent |
|---|---|
| Widgets (declarative) | SwiftUI Views |
| Riverpod Notifier | ObservableObject / @Observable ViewModel |
| `ref.watch` | `@StateObject` / `@ObservedObject` binding |
| Stream / StreamProvider | Combine Publisher / AsyncStream |
| web_socket_channel | URLSessionWebSocketTask |
| Hive | SwiftData / Core Data |
| async/await | async/await (Swift concurrency) |
