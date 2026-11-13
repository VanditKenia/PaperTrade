import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papertrade/data/api_errors.dart';
import 'package:papertrade/data/finnhub_api.dart';
import 'package:papertrade/data/market_repository.dart';

void main() {
  late int calls;
  late int status;
  late DateTime now;
  late MarketRepository repo;

  setUp(() {
    calls = 0;
    status = 200;
    now = DateTime(2026, 11, 13, 10);
    final api = FinnhubApi(
      MockClient((_) async {
        calls++;
        return http.Response('{"c": 100}', status);
      }),
      'k',
    );
    repo = MarketRepository(api, clock: () => now);
  });

  test('quote is cached for 30 s, then refetched', () async {
    await repo.quote('AAPL');
    now = now.add(const Duration(seconds: 29));
    await repo.quote('AAPL');
    expect(calls, 1);

    now = now.add(const Duration(seconds: 2));
    await repo.quote('AAPL');
    expect(calls, 2);
  });

  test('cache is per symbol', () async {
    await repo.quote('AAPL');
    await repo.quote('MSFT');
    expect(calls, 2);
  });

  test(
    'after a 429, calls fail fast for 60 s without hitting the API',
    () async {
      status = 429;
      await expectLater(repo.quote('AAPL'), throwsA(isA<RateLimitError>()));
      expect(calls, 1);

      status = 200;
      now = now.add(const Duration(seconds: 59));
      await expectLater(repo.quote('AAPL'), throwsA(isA<RateLimitError>()));
      expect(calls, 1);

      now = now.add(const Duration(seconds: 2));
      await repo.quote('AAPL');
      expect(calls, 2);
    },
  );
}
