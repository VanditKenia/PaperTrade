import 'package:flutter_test/flutter_test.dart';
import 'package:papertrade/data/api_errors.dart';
import 'package:papertrade/data/history_repository.dart';
import 'package:papertrade/domain/models/chart_range.dart';
import 'package:papertrade/domain/models/price_point.dart';

import '../fakes.dart';

void main() {
  late FakeTwelveDataApi api;
  late DateTime now;
  late HistoryRepository repo;

  setUp(() {
    api = FakeTwelveDataApi();
    now = DateTime(2026, 11, 13, 12);
    repo = HistoryRepository(api, clock: () => now);
  });

  test('ranges map to interval and outputsize', () async {
    for (final r in ChartRange.values) {
      await repo.history('AAPL', r);
    }
    await repo.history('BINANCE:BTCUSDT', ChartRange.day);
    expect(api.calls, [
      ('AAPL', '5min', 78),
      ('AAPL', '1h', 35),
      ('AAPL', '1day', 30),
      ('AAPL', '1day', 130),
      ('AAPL', '1week', 52),
      ('BINANCE:BTCUSDT', '5min', 288),
    ]);
  });

  test('1D is cached for 5 minutes', () async {
    await repo.history('AAPL', ChartRange.day);
    now = now.add(const Duration(minutes: 4, seconds: 59));
    await repo.history('AAPL', ChartRange.day);
    expect(api.calls, hasLength(1)); // cache hit
    now = now.add(const Duration(seconds: 1));
    await repo.history('AAPL', ChartRange.day);
    expect(api.calls, hasLength(2)); // expired
  });

  test('other ranges are cached for 1 hour', () async {
    await repo.history('AAPL', ChartRange.month);
    now = now.add(const Duration(minutes: 59));
    await repo.history('AAPL', ChartRange.month);
    expect(api.calls, hasLength(1));
    now = now.add(const Duration(minutes: 1));
    await repo.history('AAPL', ChartRange.month);
    expect(api.calls, hasLength(2));
  });

  test('cache is per symbol and range', () async {
    await repo.history('AAPL', ChartRange.month);
    await repo.history('AAPL', ChartRange.year);
    await repo.history('MSFT', ChartRange.month);
    expect(api.calls, hasLength(3));
  });

  test('errors are not cached', () async {
    api.error = const NetworkError();
    await expectLater(
      repo.history('AAPL', ChartRange.month),
      throwsA(isA<NetworkError>()),
    );
    api.error = null;
    await repo.history('AAPL', ChartRange.month);
    expect(api.calls, hasLength(2));
  });

  test(
    '9th request within a minute is rejected without calling the API',
    () async {
      for (var i = 0; i < 8; i++) {
        await repo.history('S$i', ChartRange.month);
        now = now.add(const Duration(seconds: 1));
      }
      await expectLater(
        repo.history('S8', ChartRange.month),
        throwsA(isA<RateLimitError>()),
      );
      expect(api.calls, hasLength(8));

      // Cached answers are still served while limited.
      await repo.history('S0', ChartRange.month);
      expect(api.calls, hasLength(8));

      // The window rolls: a minute after the first request, one slot frees.
      now = DateTime(2026, 11, 13, 12, 1);
      await repo.history('S8', ChartRange.month);
      expect(api.calls, hasLength(9));
      await expectLater(
        repo.history('S9', ChartRange.month),
        throwsA(isA<RateLimitError>()),
      );
    },
  );

  test('a server 429 blocks requests for 60 s', () async {
    api.error = const RateLimitError();
    await expectLater(
      repo.history('AAPL', ChartRange.month),
      throwsA(isA<RateLimitError>()),
    );
    api.error = null;
    now = now.add(const Duration(seconds: 59));
    await expectLater(
      repo.history('AAPL', ChartRange.month),
      throwsA(isA<RateLimitError>()),
    );
    expect(api.calls, hasLength(1));
    now = now.add(const Duration(seconds: 1));
    await repo.history('AAPL', ChartRange.month);
    expect(api.calls, hasLength(2));
  });

  test("stocks' 1D keeps only the newest session", () async {
    api.points = [
      PricePoint(time: DateTime.utc(2026, 11, 12, 20, 55), priceCents: 1),
      PricePoint(time: DateTime.utc(2026, 11, 13, 14, 30), priceCents: 2),
      PricePoint(time: DateTime.utc(2026, 11, 13, 14, 35), priceCents: 3),
    ];
    final stock = await repo.history('AAPL', ChartRange.day);
    expect(stock.map((p) => p.priceCents), [2, 3]);
    // Crypto's 1D is the last 24 h, across midnight.
    final crypto = await repo.history('BINANCE:BTCUSDT', ChartRange.day);
    expect(crypto, hasLength(3));
  });
}
