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
import 'package:papertrade/data/twelve_data_api.dart';
import 'package:papertrade/domain/models/chart_range.dart';
import 'package:papertrade/domain/models/price_point.dart';
import 'package:papertrade/domain/models/portfolio_state.dart';
import 'package:papertrade/domain/models/stock.dart';
import 'package:papertrade/domain/portfolio_engine.dart';
import 'package:papertrade/features/stock_detail/stock_detail_provider.dart';
import 'package:papertrade/features/stock_detail/stock_detail_screen.dart';
import 'package:papertrade/features/watchlist/watchlist_provider.dart';
import 'package:papertrade/data/portfolio_repository.dart';
import 'package:papertrade/domain/quantity.dart';
import 'package:papertrade/data/alert_repository.dart';

import '../../fakes.dart';

const quoteJson =
    '{"c": 189.42, "d": 1.25, "dp": 0.66, "h": 190.02, "l": 187.55,'
    ' "o": 188.10, "pc": 188.17}';

List<Override> overrides(
  Stream<Map<String, int>> live, {
  PortfolioState? portfolio,
  Override? history,
}) => [
  // Default: a proxy without a Twelve Data key answers 503.
  history ?? twelveData((_) => (503, '{"error":"not configured"}', null)),
  watchlistProvider.overrideWithBuild((_, _) => const []),
  portfolioRepositoryProvider.overrideWithValue(
    FakePortfolioRepository(portfolio),
  ),
  livePricesProvider.overrideWith((_) => live),
  alertRepositoryProvider.overrideWithValue(FakeAlertRepository()),
  // Never started, so it never opens a socket; it just records symbols.
  priceStreamServiceProvider.overrideWithValue(
    PriceStreamService(
      testProxy,
      connect: (_) => throw StateError('no socket'),
    ),
  ),
  finnhubApiProvider.overrideWithValue(
    FinnhubApi(
      MockClient((_) async => http.Response(quoteJson, 200)),
      testProxy,
    ),
  ),
];

// Two daily/5-min bars, newest first like the real API: 190.00 → 189.00.
const seriesJson =
    '{"status":"ok","values":['
    '{"datetime":"2026-11-13 15:35:00","close":"189.00"},'
    '{"datetime":"2026-11-13 15:30:00","close":"190.00"}]}';

/// Twelve Data stand-in: [respond] gets each request's URI and returns the
/// status and body (the third field just lets callers record the URI).
Override twelveData((int, String, Object?) Function(Uri) respond) =>
    twelveDataApiProvider.overrideWithValue(
      TwelveDataApi(
        MockClient((req) async {
          final (status, body, _) = respond(req.url);
          return http.Response(body, status);
        }),
        testProxy,
      ),
    );

void main() {
  group('liveTicksProvider', () {
    test("records a tick only when this symbol's price changes", () async {
      final live = StreamController<Map<String, int>>();
      addTearDown(live.close);
      final container = ProviderContainer.test(
        overrides: overrides(live.stream),
      );
      container.listen(liveTicksProvider('AAPL'), (_, _) {});

      live.add({'AAPL': 18950, 'MSFT': 40000});
      await Future<void>.delayed(Duration.zero);
      // A snapshot where only another symbol moved adds nothing.
      live.add({'AAPL': 18950, 'MSFT': 40100});
      await Future<void>.delayed(Duration.zero);
      live.add({'AAPL': 18960, 'MSFT': 40100});
      await Future<void>.delayed(Duration.zero);

      expect(
        container.read(liveTicksProvider('AAPL')).map((p) => p.priceCents),
        [18950, 18960],
      );
    });
  });

  group('chartPoints', () {
    PricePoint at(int minute, int cents) => PricePoint(
      time: DateTime.utc(2026, 11, 13, 15, minute),
      priceCents: cents,
    );
    final history = [at(0, 100), at(5, 101)];

    test('1D appends only ticks newer than the last bar', () {
      expect(
        chartPoints(ChartRange.day, history, [
          at(3, 999),
          at(6, 102),
        ]).map((p) => p.priceCents),
        [100, 101, 102],
      );
    });

    test('1D without history (no key) is just the ticks', () {
      expect(chartPoints(ChartRange.day, const [], [at(6, 102)]), hasLength(1));
    });

    test('longer ranges ignore ticks', () {
      expect(chartPoints(ChartRange.month, history, [at(6, 102)]), history);
    });
  });

  group('StockDetailScreen', () {
    Future<void> open(
      WidgetTester tester,
      Stream<Map<String, int>> live, {
      PortfolioState? portfolio,
      Override? history,
      List<Override> extra = const [],
      Stock stock = const Stock(symbol: 'AAPL', name: 'Apple Inc'),
    }) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...overrides(live, portfolio: portfolio, history: history),
            ...extra,
          ],
          child: MaterialApp(home: StockDetailScreen(stock: stock)),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows price and day stats', (tester) async {
      await open(tester, const Stream.empty());

      expect(find.text('Apple Inc'), findsOneWidget);
      expect(find.text(r'$189.42'), findsOneWidget);
      expect(find.text(r'$188.10'), findsOneWidget); // open
      expect(find.text(r'$190.02'), findsOneWidget); // high
      expect(find.text(r'$187.55'), findsOneWidget); // low
      expect(find.text(r'$188.17'), findsOneWidget); // prev close

      final sell = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'SELL'),
      );
      expect(sell.onPressed, isNull); // nothing owned yet
    });

    testWidgets('shows the position with live P&L and enables Sell', (
      tester,
    ) async {
      final owns5 = PortfolioEngine.buy(
        PortfolioState.initial(),
        symbol: 'AAPL',
        quantity: 5 * unitsPerShare,
        priceCents: 18500,
      );
      await open(tester, const Stream.empty(), portfolio: owns5);
      // The position sits below the chart; scroll it into view.
      await tester.scrollUntilVisible(
        find.text('Your position: 5 shares'),
        200,
      );

      expect(find.text('Your position: 5 shares'), findsOneWidget);
      expect(
        find.text(r'Avg cost $185.00 · P&L +$22.10', findRichText: true),
        findsOneWidget,
      );
      final sell = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'SELL'),
      );
      expect(sell.onPressed, isNotNull);
    });

    testWidgets(
      'proxy without a Twelve Data key: "History unavailable", live works',
      (tester) async {
        final live = StreamController<Map<String, int>>();
        addTearDown(live.close);
        await open(tester, live.stream);
        expect(find.text('History unavailable'), findsOneWidget);
        expect(find.text('Retry'), findsNothing); // a retry can't add a key
        expect(find.byType(LineChart), findsNothing);

        live.add({'AAPL': 18800});
        await tester.pumpAndSettle();
        live.add({'AAPL': 18700});
        await tester.pumpAndSettle();
        expect(find.byType(LineChart), findsOneWidget);
        expect(find.text(r'$187.00'), findsOneWidget);
        expect(find.text(r'▼ -$1.00 (-0.53%) today'), findsOneWidget);
        final data = tester.widget<LineChart>(find.byType(LineChart)).data;
        expect(data.lineBarsData.single.color, AppColors.loss);
      },
    );

    testWidgets('1D history + live tick: fitted axis, change vs first bar', (
      tester,
    ) async {
      final live = StreamController<Map<String, int>>();
      addTearDown(live.close);
      final requests = <Uri>[];
      await open(
        tester,
        live.stream,
        history: twelveData((uri) => (200, seriesJson, requests..add(uri))),
      );
      expect(requests.single.queryParameters['interval'], '5min');

      live.add({'AAPL': 19100});
      await tester.pumpAndSettle();
      final data = tester.widget<LineChart>(find.byType(LineChart)).data;
      expect(data.lineBarsData.single.spots.map((s) => s.y), [
        190.0,
        189.0,
        191.0,
      ]);
      expect(data.minY, closeTo(189.0 - 0.2, 1e-9)); // 10% of the $2 span
      expect(data.maxY, closeTo(191.0 + 0.2, 1e-9));
      expect(data.lineBarsData.single.isCurved, isFalse);
      expect(find.text(r'▲ +$1.00 (+0.53%) today'), findsOneWidget);
    });

    testWidgets('tapping 1M loads daily bars and drops live ticks', (
      tester,
    ) async {
      final requests = <Uri>[];
      await open(
        tester,
        const Stream.empty(),
        history: twelveData((uri) => (200, seriesJson, requests..add(uri))),
      );
      await tester.tap(find.text('1M'));
      await tester.pumpAndSettle();
      expect(requests.last.queryParameters['interval'], '1day');
      expect(requests.last.queryParameters['outputsize'], '30');
      // seriesJson goes 190 → 189: down on the range → red, "past month".
      expect(find.text(r'▼ -$1.00 (-0.53%) past month'), findsOneWidget);
    });

    testWidgets('error shows Retry; Retry loads the chart', (tester) async {
      var fail = true;
      await open(
        tester,
        const Stream.empty(),
        history: twelveData(
          (uri) => fail ? (500, '', null) : (200, seriesJson, null),
        ),
      );
      expect(find.text('Something went wrong. Retry'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(LineChart), findsOneWidget);
    });

    testWidgets('empty series shows the empty state', (tester) async {
      await open(
        tester,
        const Stream.empty(),
        history: twelveData((_) => (200, '{"status":"ok","values":[]}', null)),
      );
      expect(find.text('No chart data for this range'), findsOneWidget);
    });

    testWidgets('offline: banner shown, Buy and Sell disabled', (tester) async {
      await open(
        tester,
        const Stream.empty(),
        extra: [
          connectionStatusProvider.overrideWithValue(
            const AsyncData(ConnectionStatus.offline),
          ),
        ],
      );
      expect(find.text('Offline — showing last prices'), findsOneWidget);
      expect(find.text('Offline — trading paused'), findsOneWidget);
      final buy = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'BUY'),
      );
      expect(buy.onPressed, isNull);
    });

    testWidgets('market closed: labelled, trading still allowed', (
      tester,
    ) async {
      await open(
        tester,
        const Stream.empty(),
        extra: [marketOpenProvider.overrideWithValue(const AsyncData(false))],
      );
      expect(find.text('Market closed · last price'), findsOneWidget);
      final buy = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'BUY'),
      );
      expect(buy.onPressed, isNotNull);
    });

    testWidgets('crypto ignores market hours and counts units', (tester) async {
      await open(
        tester,
        const Stream.empty(),
        stock: const Stock(symbol: 'BINANCE:BTCUSDT', name: 'Bitcoin'),
        extra: [marketOpenProvider.overrideWithValue(const AsyncData(false))],
      );
      expect(find.text('Market closed · last price'), findsNothing);
      await tester.scrollUntilVisible(find.text('Your position: 0 units'), 200);
      expect(find.text('Your position: 0 units'), findsOneWidget);
    });
  });
}
