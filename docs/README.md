# PaperTrade — Stock Trading Simulator (Flutter)

A mobile paper-trading app: **real, live market prices — virtual money.**
Practice buying and selling stocks with a $100,000 virtual wallet, watch live P&L, and learn trading without risking real money.

> No real money, no broker connection, no payments. All trades are simulated on the device.

## Docs index

Read in this order. Each file has one job.

| File | What it covers |
|---|---|
| [PRD.md](PRD.md) | Product requirements: problem, users, features, scope, success criteria |
| [TRD.md](TRD.md) | Technical requirements: stack, APIs, data models, business rules, performance |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Layers, folder structure, data flow, state management, key design decisions |
| [APP_FLOW.md](APP_FLOW.md) | Screens, navigation, and user journeys step by step |
| [UI_UX.md](UI_UX.md) | Design system, screen layouts, states (loading/empty/error), interactions |
| [API_SPEC.md](API_SPEC.md) | Exact external API endpoints, request/response shapes, rate limits |
| [SECURITY.md](SECURITY.md) | API key handling, data storage, input validation, threat model |
| [TESTING.md](TESTING.md) | Test strategy, required unit/widget tests, manual QA checklist |
| [ROADMAP.md](ROADMAP.md) | Step-by-step feature build plan with ready-to-paste Claude Code prompts |
| [CLAUDE.md](CLAUDE.md) | Rules for Claude Code when working in this repo |
| [INTERVIEW_NOTES.md](INTERVIEW_NOTES.md) | Talking points, likely questions, resume bullet |

## Quick start (once the code exists)

```bash
flutter pub get
flutter run --dart-define=FINNHUB_API_KEY=your_key_here
flutter test
```

Get a free API key at https://finnhub.io (sign up → dashboard → API key).

## Tech stack (summary)

Flutter 3.x · Dart 3 · Riverpod · Hive CE · web_socket_channel · http · fl_chart · Finnhub API
