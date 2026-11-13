import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:papertrade/data/finnhub_api.dart';
import 'package:papertrade/domain/models/stock.dart';
import 'package:papertrade/features/watchlist/watchlist_provider.dart';
import 'package:papertrade/features/watchlist/watchlist_screen.dart';

Widget app(
  List<Stock> watchlist, {
  int status = 200,
  Stream<Map<String, int>>? live,
}) => ProviderScope(
  overrides: [
    watchlistProvider.overrideWithBuild((_, _) => watchlist),
    // Never open a real WebSocket in tests.
    livePricesProvider.overrideWith((_) => live ?? const Stream.empty()),
    finnhubApiProvider.overrideWithValue(
      FinnhubApi(
        MockClient(
          (_) async => http.Response(
            '{"c": 189.42, "d": 1.25, "dp": 0.6643, "pc": 188.17}',
            status,
          ),
        ),
        'k',
      ),
    ),
  ],
  child: const MaterialApp(home: WatchlistScreen()),
);

void main() {
  testWidgets('empty watchlist shows the Search stocks button', (tester) async {
    await tester.pumpWidget(app(const []));
    expect(find.text('Your watchlist is empty'), findsOneWidget);
    expect(find.text('Search stocks'), findsOneWidget);
  });

  testWidgets('shows price and signed change for each stock', (tester) async {
    await tester.pumpWidget(
      app(const [Stock(symbol: 'AAPL', name: 'Apple Inc')]),
    );
    await tester.pumpAndSettle();
    expect(find.text('AAPL'), findsOneWidget);
    expect(find.text(r'$189.42'), findsOneWidget);
    expect(find.text(r'▲ +$1.25 (+0.66%)'), findsOneWidget);
  });

  testWidgets('API error is shown on the tile', (tester) async {
    await tester.pumpWidget(
      app(const [Stock(symbol: 'AAPL', name: 'Apple Inc')], status: 401),
    );
    await tester.pumpAndSettle();
    expect(find.text('API key invalid — check configuration'), findsOneWidget);
  });

  testWidgets('live tick replaces the quote price and flashes for 300 ms', (
    tester,
  ) async {
    final live = StreamController<Map<String, int>>();
    addTearDown(live.close);
    await tester.pumpWidget(
      app(const [Stock(symbol: 'AAPL', name: 'Apple Inc')], live: live.stream),
    );
    await tester.pumpAndSettle();

    Color? tint() =>
        (tester
                    .widget<DecoratedBox>(
                      find
                          .ancestor(
                            of: find.textContaining(r'$1'),
                            matching: find.byType(DecoratedBox),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration)
            .color;

    live.add({'AAPL': 18717}); // down $1.00 from the quote, below prev close
    await tester.pump(); // deliver the stream event
    await tester.pump(); // rebuild the tile
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text(r'$187.17'), findsOneWidget);
    expect(find.text(r'▼ -$1.00 (-0.53%)'), findsOneWidget);
    expect(tint(), isNotNull); // red flash in progress

    await tester.pump(const Duration(milliseconds: 250));
    expect(tint(), isNull); // faded out after 300 ms
  });
}
