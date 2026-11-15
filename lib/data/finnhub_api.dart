import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/money.dart';
import '../domain/models/quote.dart';
import '../domain/models/stock.dart';
import 'api_errors.dart';

final finnhubApiProvider = Provider<FinnhubApi>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  // Only built once the app is past the setup screen, so a proxy exists.
  return FinnhubApi(client, proxyUri!);
});

/// Market data via our proxy's Finnhub routes (API_SPEC.md §2). The proxy
/// adds the key, so nothing here is secret. Throws only [ApiError]s.
class FinnhubApi {
  FinnhubApi(this._client, this._proxy, {this._isWeb = kIsWeb});

  final http.Client _client;
  final Uri _proxy; // https://host of the Worker
  final bool _isWeb;

  static const _webNetworkMessage = "Couldn't reach market data. Retry";

  static const _timeout = Duration(seconds: 10);

  Future<List<Stock>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    // The proxy fixes exchange=US itself.
    final json = await _get('/search', {
      'q': q.length > 50 ? q.substring(0, 50) : q,
    });
    final result = json['result'];
    if (result is! List) return const [];
    return [
      for (final item in result)
        if (item is Map &&
            item['type'] == 'Common Stock' &&
            item['symbol'] is String &&
            item['description'] is String)
          Stock(
            symbol: item['symbol'] as String,
            name: item['description'] as String,
          ),
    ];
  }

  Future<Quote> quote(String symbol) async {
    final json = await _get('/quote', {'symbol': symbol});
    final current = json['c'];
    // Finnhub answers an unknown symbol with all zeros (or nulls), not a 404.
    if (current is! num || !current.isFinite || current <= 0) {
      throw const PriceUnavailableError();
    }
    // Optional fields fall back to 0 so one missing stat can't hide the price.
    int cents(Object? v) => v is num && v.isFinite ? toCents(v.toDouble()) : 0;
    final dp = json['dp'];
    final t = json['t'];
    return Quote(
      symbol: symbol,
      currentCents: toCents(current.toDouble()),
      changeCents: cents(json['d']),
      changePercent: dp is num && dp.isFinite ? dp.toDouble() : 0,
      highCents: cents(json['h']),
      lowCents: cents(json['l']),
      openCents: cents(json['o']),
      prevCloseCents: cents(json['pc']),
      timestamp: t is int
          ? DateTime.fromMillisecondsSinceEpoch(t * 1000)
          : DateTime.now(),
    );
  }

  /// Whether the US market is open now (API_SPEC.md §2.4).
  Future<bool> isMarketOpen() async {
    final json = await _get('/market-status', const {});
    final open = json['isOpen'];
    if (open is! bool) throw const UnknownError();
    return open;
  }

  Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> params,
  ) async {
    // No custom headers: on web they would add a CORS preflight per call.
    final uri = Uri.https(_proxy.authority, path, params);
    final http.Response res;
    try {
      res = await _client.get(uri).timeout(_timeout);
    } on TimeoutException {
      throw const NetworkError();
    } on http.ClientException catch (e) {
      _log('$path failed: ${e.message}');
      // On mobile this wraps SocketException (no network, DNS failure). On
      // web the browser hides the cause (offline, CORS, blocked...), so
      // don't claim "offline".
      throw _isWeb
          ? const NetworkError(_webNetworkMessage)
          : const NetworkError();
    }

    switch (res.statusCode) {
      case 200:
        break;
      case 401 || 403:
        throw const AuthError();
      case 429:
        throw const RateLimitError();
      default:
        throw const UnknownError();
    }

    try {
      final body = jsonDecode(res.body);
      if (body is Map<String, dynamic>) return body;
    } on FormatException {
      // fall through
    }
    throw const UnknownError();
  }

  void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }
}
