import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papertrade/data/finnhub_api.dart';
import 'package:papertrade/data/portfolio_repository.dart';
import 'package:papertrade/data/price_stream_service.dart';
import 'package:papertrade/features/portfolio/order_matcher_provider.dart';
import 'package:papertrade/features/portfolio/portfolio_provider.dart';
import 'package:papertrade/features/watchlist/price_subscriptions_provider.dart';
import 'package:papertrade/features/watchlist/watchlist_provider.dart';
import 'package:papertrade/domain/quantity.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../fakes.dart';

/// Socket that connects and records what the app sends.
class _FakeChannel extends Fake implements WebSocketChannel {
  final sent = <String>[];
  // Never closes: a closed stream would look like a dropped connection.
  final _server = StreamController<dynamic>();

  @override
  Stream<dynamic> get stream => _server.stream;

  @override
  Future<void> get ready async {}

  @override
  WebSocketSink get sink => _FakeSink(sent);
}

class _FakeSink extends Fake implements WebSocketSink {
  _FakeSink(this.sent);

  final List<String> sent;

  @override
  void add(dynamic data) => sent.add(data as String);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}
}

void main() {
  // Regression: buying used to read latestPriceProvider from inside the
  // notifier while the price providers watched the portfolio, which threw
  // CircularDependencyError. Only network and storage are faked here; every
  // provider between them is real (no latestPriceProvider override).
  test('buy and sell through the real providers without a cycle', () async {
    final channel = _FakeChannel();
    final service = PriceStreamService(testProxy, connect: (_) => channel);
    final container = ProviderContainer.test(
      overrides: [
        portfolioRepositoryProvider.overrideWithValue(
          FakePortfolioRepository(),
        ),
        watchlistProvider.overrideWithBuild((_, _) => const []),
        priceStreamServiceProvider.overrideWithValue(service),
        finnhubApiProvider.overrideWithValue(
          FinnhubApi(
            MockClient(
              (_) async => http.Response('{"c": 189.42, "pc": 188.17}', 200),
            ),
            testProxy,
          ),
        ),
      ],
    );
    // Listen like the open screens do, so every link of the old cycle is
    // alive: shell → subscriptions, portfolio screen → summary → prices,
    // order sheet → latest price.
    final errors = <Object>[];
    void onError(Object e, StackTrace _) => errors.add(e);
    container
      ..listen(priceSubscriptionsProvider, (_, _) {}, onError: onError)
      ..listen(orderMatcherProvider, (_, _) {}, onError: onError)
      ..listen(portfolioSummaryProvider, (_, _) {}, onError: onError)
      ..listen(latestPriceProvider('AAPL'), (_, _) {}, onError: onError);
    await container.read(quoteProvider('AAPL').future);

    final price = container.read(latestPriceProvider('AAPL'))!;
    final portfolio = container.read(portfolioProvider.notifier);
    await portfolio.buy('AAPL', 5 * unitsPerShare, priceCents: price);
    await portfolio.sell('AAPL', 2 * unitsPerShare, priceCents: price);
    await Future<void>.delayed(Duration.zero);

    expect(errors, isEmpty);
    expect(
      container.read(portfolioProvider).holdings['AAPL']!.quantity,
      3 * unitsPerShare,
    );
    expect(
      container.read(portfolioSummaryProvider).marketValueCents,
      3 * price,
    );

    // The held symbol was subscribed via the separate subscriptions provider.
    service.start();
    await Future<void>.delayed(Duration.zero);
    expect(
      channel.sent,
      contains(jsonEncode({'type': 'subscribe', 'symbol': 'AAPL'})),
    );
    service.dispose();
  });
}
