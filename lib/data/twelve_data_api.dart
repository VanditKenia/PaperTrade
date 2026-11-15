import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/money.dart';
import '../domain/models/price_point.dart';
import 'api_errors.dart';

final twelveDataApiProvider = Provider<TwelveDataApi>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  // Only built once the app is past the setup screen, so a proxy exists.
  return TwelveDataApi(client, proxyUri!);
});

/// Chart history via our proxy's `/history` route, which forwards to
/// Twelve Data `/time_series` (API_SPEC.md §4). Throws only [ApiError]s.
class TwelveDataApi {
  TwelveDataApi(this._client, this._proxy);

  final http.Client _client;
  final Uri _proxy; // https://host of the Worker

  static const _timeout = Duration(seconds: 10);

  /// Closes (oldest first) for [symbol] at [interval] ("5min", "1day"…).
  Future<List<PricePoint>> timeSeries(
    String symbol, {
    required String interval,
    required int outputSize,
  }) async {
    // The proxy adds timezone=UTC (so datetimes parse without knowing the
    // exchange's time zone) and the key.
    final uri = Uri.https(_proxy.authority, '/history', {
      'symbol': mapSymbol(symbol),
      'interval': interval,
      'outputsize': '$outputSize',
    });
    final http.Response res;
    try {
      res = await _client.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const NetworkError();
    } on http.ClientException {
      throw const NetworkError();
    }

    Object? body;
    try {
      body = jsonDecode(res.body);
    } on FormatException {
      body = null;
    }
    // Twelve Data often reports errors as HTTP 200 with a "code" in the
    // body, so the body's code wins over the HTTP status.
    final json = body is Map ? body : const {};
    final code = json['status'] == 'error' && json['code'] is int
        ? json['code'] as int
        : res.statusCode;
    switch (code) {
      case 200:
        break;
      // 503: the proxy has no Twelve Data key. History is optional, so
      // that's "unavailable", not a crash.
      case 400 || 404 || 503:
        throw const HistoryUnavailableError();
      case 401 || 403:
        throw const AuthError();
      case 429:
        throw const RateLimitError();
      default:
        throw const UnknownError();
    }
    if (body is! Map) throw const UnknownError();
    return parseValues(json['values']);
  }

  /// Our symbols → Twelve Data's: BINANCE:BTCUSDT → BTC/USD. US stocks are
  /// the same on both.
  static String mapSymbol(String symbol) {
    const prefix = 'BINANCE:';
    if (!symbol.startsWith(prefix)) return symbol;
    final pair = symbol.substring(prefix.length);
    return pair.endsWith('USDT')
        ? '${pair.substring(0, pair.length - 4)}/USD'
        : pair;
  }

  /// Parses `values` (strings, newest first) into points, oldest first.
  /// Rows with a bad date or price are skipped, never thrown on.
  static List<PricePoint> parseValues(Object? values) {
    if (values is! List) return const [];
    final points = <PricePoint>[];
    for (final row in values) {
      if (row is! Map) continue;
      final time = _parseUtc(row['datetime']);
      final close = row['close'];
      final price = close is String ? double.tryParse(close) : null;
      if (time == null || price == null || !price.isFinite || price <= 0) {
        continue;
      }
      points.add(PricePoint(time: time, priceCents: toCents(price)));
    }
    points.sort((a, b) => a.time.compareTo(b.time));
    return points;
  }

  /// "2026-11-11" or "2026-11-11 15:55:00", in UTC (we ask for timezone=UTC).
  static DateTime? _parseUtc(Object? raw) {
    if (raw is! String) return null;
    final iso = raw.length == 10
        ? '${raw}T00:00:00'
        : raw.replaceFirst(' ', 'T');
    return DateTime.tryParse('${iso}Z');
  }
}
