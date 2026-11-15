import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertrade/data/api_errors.dart';
import 'package:papertrade/data/history_repository.dart';
import 'package:papertrade/domain/models/chart_range.dart';
import 'package:papertrade/features/stock_detail/stock_detail_provider.dart';

import '../../fakes.dart';

void main() {
  late FakeTwelveDataApi api;
  late ProviderContainer container;
  const key = (symbol: 'AAPL', range: ChartRange.month);

  setUp(() {
    api = FakeTwelveDataApi();
    // Only the repository is overridden: the portfolio repository is left
    // unconfigured on purpose, so reading the portfolio would throw.
    container = ProviderContainer.test(
      overrides: [
        historyRepositoryProvider.overrideWithValue(HistoryRepository(api)),
      ],
    );
  });

  test('loads points for the symbol and range', () async {
    container.listen(historyProvider(key), (_, _) {});
    final points = await container.read(historyProvider(key).future);
    expect(points.single.priceCents, 100);
    expect(api.calls, [('AAPL', '1day', 30)]);
  });

  test(
    'error is exposed, not retried automatically; reload() fetches',
    () async {
      api.error = const NetworkError();
      container.listen(historyProvider(key), (_, _) {});
      await expectLater(
        container.read(historyProvider(key).future),
        throwsA(isA<NetworkError>()),
      );
      expect(container.read(historyProvider(key)).error, isA<NetworkError>());
      expect(api.calls, hasLength(1));

      api.error = null;
      container.read(historyProvider(key).notifier).reload();
      final points = await container.read(historyProvider(key).future);
      expect(points, hasLength(1));
      expect(api.calls, hasLength(2));
    },
  );

  test('switching ranges back is served from the cache', () async {
    const day = (symbol: 'AAPL', range: ChartRange.day);
    container.listen(historyProvider(key), (_, _) {});
    container.listen(historyProvider(day), (_, _) {});
    await container.read(historyProvider(key).future);
    await container.read(historyProvider(day).future);

    // A fresh provider for the same key (e.g. detail screen reopened).
    container.invalidate(historyProvider(key));
    await container.read(historyProvider(key).future);
    expect(api.calls, hasLength(2));
  });
}
