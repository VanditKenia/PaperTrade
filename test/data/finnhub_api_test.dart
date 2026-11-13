import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papertrade/data/api_errors.dart';
import 'package:papertrade/data/finnhub_api.dart';

FinnhubApi apiReturning(Object body, {int status = 200}) => FinnhubApi(
  MockClient(
    (_) async =>
        http.Response(body is String ? body : jsonEncode(body), status),
  ),
  'test-key',
);

void main() {
  group('quote', () {
    test('parses prices into cents', () async {
      final q = await apiReturning({
        'c': 189.42,
        'd': -1.25,
        'dp': -0.6643,
        'h': 190.02,
        'l': 187.55,
        'o': 188.1,
        'pc': 188.17,
        't': 1731430000,
      }).quote('AAPL');
      expect(q.symbol, 'AAPL');
      expect(q.currentCents, 18942);
      expect(q.changeCents, -125);
      expect(q.changePercent, -0.6643);
      expect(q.highCents, 19002);
      expect(q.openCents, 18810);
      expect(q.prevCloseCents, 18817);
      expect(q.timestamp.millisecondsSinceEpoch, 1731430000000);
    });

    test('all zeros means unknown symbol → PriceUnavailableError', () {
      expect(
        apiReturning({'c': 0, 'd': null, 'dp': null, 'pc': 0}).quote('XYZ'),
        throwsA(isA<PriceUnavailableError>()),
      );
    });

    test('sends symbol and key as query params, no custom headers', () async {
      late http.Request sent;
      final api = FinnhubApi(
        MockClient((req) async {
          sent = req;
          return http.Response('{"c": 1}', 200);
        }),
        'test-key',
      );
      await api.quote('BINANCE:BTCUSDT');
      expect(sent.url.scheme, 'https');
      expect(sent.url.queryParameters, {
        'symbol': 'BINANCE:BTCUSDT',
        'token': 'test-key',
      });
      // Any custom header triggers a CORS preflight on web.
      expect(sent.headers, isEmpty);
    });
  });

  group('search', () {
    test('keeps only common stocks', () async {
      final results = await apiReturning({
        'result': [
          {
            'symbol': 'NVDA',
            'description': 'NVIDIA CORP',
            'type': 'Common Stock',
          },
          {'symbol': 'NVDX', 'description': 'SOME ETF', 'type': 'ETP'},
          {'symbol': 42, 'description': 'bad row', 'type': 'Common Stock'},
        ],
      }).search('nvidia');
      expect(results.map((s) => s.symbol), ['NVDA']);
      expect(results.single.name, 'NVIDIA CORP');
    });

    test('blank query makes no request', () async {
      final api = FinnhubApi(
        MockClient((_) async => fail('should not call the API')),
        'k',
      );
      expect(await api.search('   '), isEmpty);
    });
  });

  group('error mapping', () {
    test('401 and 403 → AuthError', () {
      expect(
        apiReturning('', status: 401).quote('A'),
        throwsA(isA<AuthError>()),
      );
      expect(
        apiReturning('', status: 403).quote('A'),
        throwsA(isA<AuthError>()),
      );
    });

    test('429 → RateLimitError', () {
      expect(
        apiReturning('', status: 429).quote('A'),
        throwsA(isA<RateLimitError>()),
      );
    });

    test('500 and malformed JSON → UnknownError', () {
      expect(
        apiReturning('', status: 500).quote('A'),
        throwsA(isA<UnknownError>()),
      );
      expect(apiReturning('not json').quote('A'), throwsA(isA<UnknownError>()));
      expect(apiReturning('[1, 2]').quote('A'), throwsA(isA<UnknownError>()));
    });

    FinnhubApi failing({required bool isWeb}) => FinnhubApi(
      MockClient(
        (req) async =>
            throw http.ClientException('Failed to fetch ${req.url}', req.url),
      ),
      'secret-key',
      isWeb: isWeb,
    );

    test('connection failure on mobile → "You\'re offline"', () {
      expect(
        failing(isWeb: false).quote('A'),
        throwsA(
          isA<NetworkError>().having(
            (e) => e.message,
            'message',
            "You're offline",
          ),
        ),
      );
    });

    test('connection failure on web → generic network error', () {
      expect(
        failing(isWeb: true).quote('A'),
        throwsA(
          isA<NetworkError>().having(
            (e) => e.message,
            'message',
            "Couldn't reach market data. Retry",
          ),
        ),
      );
    });

    test('failure is logged with the path but never the token', () async {
      final logs = <String>[];
      final original = debugPrint;
      debugPrint = (message, {wrapWidth}) => logs.add(message ?? '');
      addTearDown(() => debugPrint = original);

      await expectLater(
        failing(isWeb: true).quote('A'),
        throwsA(isA<NetworkError>()),
      );
      expect(logs, hasLength(1));
      expect(logs.single, startsWith('/api/v1/quote failed:'));
      expect(logs.single, isNot(contains('secret-key')));
    });
  });
}
