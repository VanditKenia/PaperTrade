import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:papertrade/core/theme.dart';
import 'package:papertrade/data/finnhub_api.dart';
import 'package:papertrade/data/price_stream_service.dart';
import 'package:papertrade/domain/models/stock.dart';
import 'package:papertrade/features/stock_detail/stock_detail_provider.dart';
import 'package:papertrade/features/stock_detail/stock_detail_screen.dart';
import 'package:papertrade/features/watchlist/watchlist_provider.dart';

const quoteJson =
    '{"c": 189.42, "d": 1.25, "dp": 0.66, "h": 190.02, "l": 187.55,'
    ' "o": 188.10, "pc": 188.17}';

List<Override> overrides(Stream<Map<String, int>> live) => [
  watchlistProvider.overrideWithBuild((_, _) => const []),
  livePricesProvider.overrideWith((_) => live),
  // Never started, so it never opens a socket; it just records symbols.
  priceStreamServiceProvider.overrideWithValue(
    PriceStreamService('k', connect: (_) => throw StateError('no socket')),
  ),
  finnhubApiProvider.overrideWithValue(
    FinnhubApi(MockClient((_) async => http.Response(quoteJson, 200)), 'k'),
  ),
];

void main() {
  group('chartPointsProvider', () {
    test('seeds prevClose → open → current, then appends live ticks', () async {
      final live = StreamController<Map<String, int>>();
      addTearDown(live.close);
      final container = ProviderContainer.test(
        overrides: overrides(live.stream),
      );
      container.listen(chartPointsProvider('AAPL'), (_, _) {});

      await container.read(quoteProvider('AAPL').future);
      expect(container.read(chartPointsProvider('AAPL')).visible, [
        18817,
        18810,
        18942,
      ]);

      live.add({'AAPL': 18950, 'MSFT': 40000});
      await Future<void>.delayed(Duration.zero);
      // A snapshot where only another symbol moved adds nothing.
      live.add({'AAPL': 18950, 'MSFT': 40100});
      await Future<void>.delayed(Duration.zero);
      live.add({'AAPL': 18960, 'MSFT': 40100});
      await Future<void>.delayed(Duration.zero);

      expect(container.read(chartPointsProvider('AAPL')).visible, [
        18817,
        18810,
        18942,
        18950,
        18960,
      ]);
    });
  });

  group('ChartPoints.visible', () {
    const seed = [18817, 18810, 18942];

    test('shows seed + live while fewer than 10 ticks', () {
      final live = List.generate(9, (i) => 19000 + i);
      expect(ChartPoints(seed: seed, live: live).visible, [...seed, ...live]);
    });

    test('drops the seed once 10 ticks have arrived', () {
      final live = List.generate(10, (i) => 19000 + i);
      expect(ChartPoints(seed: seed, live: live).visible, live);
    });
  });

  group('StockDetailScreen', () {
    Future<void> open(
      WidgetTester tester,
      Stream<Map<String, int>> live,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(live),
          child: const MaterialApp(
            home: StockDetailScreen(
              stock: Stock(symbol: 'AAPL', name: 'Apple Inc'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows price, change, day stats and a seeded chart', (
      tester,
    ) async {
      await open(tester, const Stream.empty());

      expect(find.text('Apple Inc'), findsOneWidget);
      expect(find.text(r'$189.42'), findsOneWidget);
      expect(find.text(r'▲ +$1.25 (+0.66%) today'), findsOneWidget);
      expect(find.text(r'$188.10'), findsOneWidget); // open
      expect(find.text(r'$190.02'), findsOneWidget); // high
      expect(find.text(r'$187.55'), findsOneWidget); // low
      expect(find.text(r'$188.17'), findsOneWidget); // prev close
      expect(find.byType(LineChart), findsOneWidget);

      final sell = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'SELL'),
      );
      expect(sell.onPressed, isNull); // nothing owned yet
    });

    testWidgets('live price below prev close turns the header red', (
      tester,
    ) async {
      final live = StreamController<Map<String, int>>();
      addTearDown(live.close);
      await open(tester, live.stream);

      live.add({'AAPL': 18717});
      await tester.pumpAndSettle();
      expect(find.text(r'$187.17'), findsOneWidget);
      expect(find.text(r'▼ -$1.00 (-0.53%) today'), findsOneWidget);
    });

    List<HorizontalLine> dashedLines(WidgetTester tester) => tester
        .widget<LineChart>(find.byType(LineChart))
        .data
        .extraLinesData
        .horizontalLines;

    testWidgets('prev close line shows while it is inside the range', (
      tester,
    ) async {
      await open(tester, const Stream.empty());
      // Seed points include prev close itself, so it's always in range.
      expect(dashedLines(tester).single.y, 188.17);
    });

    testWidgets('after 10 ticks the y-axis fits the ticks; prev close far '
        'outside the range is hidden', (tester) async {
      final live = StreamController<Map<String, int>>();
      addTearDown(live.close);
      await open(tester, live.stream);

      for (var i = 0; i < 10; i++) {
        live.add({'AAPL': 19500 + i}); // $195.00–$195.09, far above $188.17
        await tester.pumpAndSettle();
      }
      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      expect(data.lineBarsData.single.spots, hasLength(10));
      expect(data.minY, closeTo(195.00 - 0.01, 1e-9)); // 10% of $0.09 < 1¢
      expect(data.maxY, closeTo(195.09 + 0.01, 1e-9));
      expect(dashedLines(tester), isEmpty);
      // Still colored by the day: $195 is above prev close → green.
      expect(data.lineBarsData.single.color, AppColors.gain);
    });
  });
}
