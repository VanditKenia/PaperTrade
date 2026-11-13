import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/quote.dart';
import '../domain/models/stock.dart';
import 'api_errors.dart';
import 'finnhub_api.dart';

final marketRepositoryProvider = Provider<MarketRepository>(
  (ref) => MarketRepository(ref.watch(finnhubApiProvider)),
);

/// Market data for the app. Caches quotes so screens can ask freely without
/// burning the 60 calls/min free-tier limit.
class MarketRepository {
  MarketRepository(this._api, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final FinnhubApi _api;
  final DateTime Function() _now;

  static const _quoteTtl = Duration(seconds: 30);
  static const _rateLimitBackoff = Duration(seconds: 60);

  final _quotes = <String, ({Quote quote, DateTime fetchedAt})>{};
  DateTime? _rateLimitedUntil;

  Future<List<Stock>> search(String query) => _call(() => _api.search(query));

  Future<Quote> quote(String symbol) async {
    final cached = _quotes[symbol];
    if (cached != null && _now().difference(cached.fetchedAt) < _quoteTtl) {
      return cached.quote;
    }
    final quote = await _call(() => _api.quote(symbol));
    _quotes[symbol] = (quote: quote, fetchedAt: _now());
    return quote;
  }

  // After a 429, more calls would only extend the ban, so fail fast for 60 s.
  Future<T> _call<T>(Future<T> Function() request) async {
    final until = _rateLimitedUntil;
    if (until != null && _now().isBefore(until)) throw const RateLimitError();
    try {
      return await request();
    } on RateLimitError {
      _rateLimitedUntil = _now().add(_rateLimitBackoff);
      rethrow;
    }
  }
}
