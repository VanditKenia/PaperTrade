import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:papertrade/data/api_errors.dart';
import 'package:papertrade/data/twelve_data_api.dart';

import '../fakes.dart';

TwelveDataApi apiReturning(
  Object body, {
  int status = 200,
  List<Uri>? requests,
}) => TwelveDataApi(
  MockClient((req) async {
    requests?.add(req.url);
    return http.Response(body is String ? body : jsonEncode(body), status);
  }),
  testProxy,
);

Future<void> fetch(TwelveDataApi api) =>
    api.timeSeries('AAPL', interval: '1day', outputSize: 30);

void main() {
  group('parseValues', () {
    test('string closes → cents, oldest first, dates as UTC', () {
      final points = TwelveDataApi.parseValues([
        {'datetime': '2026-11-12', 'close': '189.425'},
        {'datetime': '2026-11-11', 'close': '188.10'},
      ]);
      expect(points.map((p) => p.priceCents), [18810, 18943]);
      expect(points.first.time, DateTime.utc(2026, 11, 11));
    });

    test('intraday datetimes keep their time', () {
      final p = TwelveDataApi.parseValues([
        {'datetime': '2026-11-13 15:55:00', 'close': '1'},
      ]).single;
      expect(p.time, DateTime.utc(2026, 11, 13, 15, 55));
    });

    test('bad rows are skipped, good ones kept', () {
      final points = TwelveDataApi.parseValues([
        {'datetime': '2026-11-11', 'close': 'abc'},
        {'datetime': '2026-11-11', 'close': 189.42}, // number, not string
        {'datetime': '2026-11-11', 'close': '-1'},
        {'datetime': '2026-11-11', 'close': '0'},
        {'datetime': '2026-11-11', 'close': 'NaN'},
        {'datetime': 'yesterday', 'close': '1'},
        {'close': '1'},
        'junk',
        null,
        {'datetime': '2026-11-12', 'close': '190.00'},
      ]);
      expect(points.map((p) => p.priceCents), [19000]);
    });

    test('values that are not a list → empty', () {
      expect(TwelveDataApi.parseValues(null), isEmpty);
      expect(TwelveDataApi.parseValues('oops'), isEmpty);
    });
  });

  group('mapSymbol', () {
    test('Binance USDT pairs → Twelve Data crypto pairs', () {
      expect(TwelveDataApi.mapSymbol('BINANCE:BTCUSDT'), 'BTC/USD');
      expect(TwelveDataApi.mapSymbol('BINANCE:ETHUSDT'), 'ETH/USD');
    });

    test('US stocks are unchanged', () {
      expect(TwelveDataApi.mapSymbol('AAPL'), 'AAPL');
      expect(TwelveDataApi.mapSymbol('BRK.B'), 'BRK.B');
    });
  });

  group('timeSeries', () {
    test('calls the proxy over https, with no key', () async {
      final requests = <Uri>[];
      await apiReturning(
        {'status': 'ok', 'values': <Object>[]},
        requests: requests,
      ).timeSeries('BINANCE:BTCUSDT', interval: '5min', outputSize: 288);
      final uri = requests.single;
      expect(uri.scheme, 'https');
      expect(uri.host, 'proxy.test');
      expect(uri.path, '/history');
      // The proxy adds timezone and the key.
      expect(uri.queryParameters, {
        'symbol': 'BTC/USD',
        'interval': '5min',
        'outputsize': '288',
      });
    });

    test('proxy without a Twelve Data key (503) → HistoryUnavailable', () {
      expect(
        fetch(apiReturning({'error': 'not configured'}, status: 503)),
        throwsA(isA<HistoryUnavailableError>()),
      );
    });

    test('maps "status":"error" codes in a 200 body', () async {
      for (final (code, matcher) in [
        (400, isA<HistoryUnavailableError>()),
        (404, isA<HistoryUnavailableError>()),
        (401, isA<AuthError>()),
        (429, isA<RateLimitError>()),
        (500, isA<UnknownError>()),
      ]) {
        await expectLater(
          fetch(
            apiReturning({'status': 'error', 'code': code, 'message': 'x'}),
          ),
          throwsA(matcher),
          reason: '$code',
        );
      }
    });

    test('maps HTTP status codes', () async {
      await expectLater(
        fetch(apiReturning('', status: 401)),
        throwsA(isA<AuthError>()),
      );
      await expectLater(
        fetch(apiReturning('', status: 429)),
        throwsA(isA<RateLimitError>()),
      );
    });

    test('non-JSON 200 → UnknownError', () async {
      await expectLater(
        fetch(apiReturning('<html>')),
        throwsA(isA<UnknownError>()),
      );
    });
  });
}
