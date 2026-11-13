# CLAUDE.md — Instructions for Claude Code

You are helping build **PaperTrade**, a Flutter paper-trading app. The developer is learning while building and must be able to explain every line in a job interview.

## Source of truth

Project docs live in `/docs`. Read the relevant ones before each step:
PRD.md · TRD.md · ARCHITECTURE.md · APP_FLOW.md · UI_UX.md · API_SPEC.md · SECURITY.md · TESTING.md · ROADMAP.md

If code and docs disagree, ask before changing either.

## How to work

1. Build **only the current ROADMAP step**. Do not jump ahead or add unrequested features.
2. Keep changes small and readable. Prefer clear code over clever code.
3. After finishing a step:
   - run `flutter analyze` and `flutter test`
   - summarize what files were created/changed
   - **explain the key concepts in simple terms** (the developer will study them)
   - suggest the commit message from ROADMAP.md
4. Add short comments explaining *why* on non-obvious logic (throttling, avg cost, reconnect backoff). No comments that just restate the code.

## Hard rules

- **Money is always `int` cents.** Never use `double` for balances, costs or P&L. Convert API prices with `(price * 100).round()`.
- `domain/` is pure Dart — no `package:flutter` imports.
- UI never calls `http`, WebSocket, or Hive directly — go through providers → repositories.
- PortfolioEngine is immutable: input state → new state or typed error.
- **Never hardcode or log the API key.** Read it with `String.fromEnvironment('FINNHUB_API_KEY')`.
- Only `https://` / `wss://`.
- Build URLs with `Uri.https(...)` + `queryParameters`, never string concatenation.
- Parse all network data defensively; a bad message must never crash the app or the stream.
- Every data screen handles loading / empty / error / offline states (UI_UX.md §4).
- Use `FontFeature.tabularFigures()` for prices.
- Null-safe Dart 3, zero analyzer warnings.

## Conventions

- Files: `snake_case.dart`. Classes: `PascalCase`. Providers end with `Provider`.
- One widget per file for screens and major widgets.
- Riverpod: use `Notifier`/`AsyncNotifier` (not legacy `StateNotifier`).
- Tests mirror `lib/` structure under `test/`.
- Commit style: `feat:`, `fix:`, `chore:`, `docs:`, `test:`.

## Commands

```bash
flutter pub get
flutter run --dart-define=FINNHUB_API_KEY=$FINNHUB_API_KEY
flutter test
flutter analyze
```
