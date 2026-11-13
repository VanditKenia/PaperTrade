import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papertrade/data/finnhub_api.dart';
import 'package:papertrade/features/search/search_provider.dart';

void main() {
  test('debounces typing into a single search for the final text', () async {
    final queries = <String?>[];
    final container = ProviderContainer.test(
      overrides: [
        finnhubApiProvider.overrideWithValue(
          FinnhubApi(
            MockClient((req) async {
              queries.add(req.url.queryParameters['q']);
              return http.Response(
                '{"result": [{"symbol": "NVDA", "description": "NVIDIA CORP",'
                ' "type": "Common Stock"}]}',
                200,
              );
            }),
            'k',
          ),
        ),
      ],
    );
    // Keep the autoDispose provider alive like an open screen would.
    container.listen(searchProvider, (_, _) {});
    final notifier = container.read(searchProvider.notifier);

    for (final text in ['n', 'nv', 'nvi', 'nvidia']) {
      notifier.setQuery(text);
    }
    expect(queries, isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(queries, ['nvidia']);
    expect(container.read(searchProvider).value!.single.symbol, 'NVDA');
  });

  test('clearing the text returns to idle without a request', () {
    final container = ProviderContainer.test();
    container.listen(searchProvider, (_, _) {});
    container.read(searchProvider.notifier).setQuery('   ');
    expect(container.read(searchProvider).value, isNull);
  });
}
