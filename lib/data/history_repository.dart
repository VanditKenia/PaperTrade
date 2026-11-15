import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/chart_range.dart';
import '../domain/models/price_point.dart';
import '../domain/models/stock.dart';
import 'api_errors.dart';
import 'twelve_data_api.dart';

final historyRepositoryProvider = Provider<HistoryRepository>(
  (ref) => HistoryRepository(ref.watch(twelveDataApiProvider)),
);

/// Chart history with an in-memory cache and a client-side rate limit, so
/// flipping between ranges and stocks stays inside Twelve Data's free tier
/// (8 requests/min).
class HistoryRepository {
  HistoryRepository(this._api, {DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  final TwelveDataApi _api;
  final DateTime Function() _now;

  static const maxRequestsPerMinute = 8;
  static const _window = Duration(minutes: 1);
  static const _rateLimitBackoff = Duration(seconds: 60);

  final _cache =
      <(String, ChartRange), ({List<PricePoint> points, DateTime at})>{};
  final _sent = <DateTime>[]; // request times within the last minute
  DateTime? _rateLimitedUntil;

  Future<List<PricePoint>> history(String symbol, ChartRange range) async {
    final key = (symbol, range);
    final cached = _cache[key];
    if (cached != null && _now().difference(cached.at) < _ttl(range)) {
      return cached.points;
    }

    _checkRateLimit();
    _sent.add(_now());
    final crypto = isCrypto(symbol);
    final (interval, size) = switch (range) {
      ChartRange.day => ('5min', crypto ? 288 : 78), // 24 h, or one session
      ChartRange.week => ('1h', crypto ? 168 : 35), // 7 days, or 5 sessions
      ChartRange.month => ('1day', 30),
      ChartRange.sixMonths => ('1day', 130),
      ChartRange.year => ('1week', 52),
    };
    final List<PricePoint> points;
    try {
      points = await _api.timeSeries(
        symbol,
        interval: interval,
        outputSize: size,
      );
    } on RateLimitError {
      _rateLimitedUntil = _now().add(_rateLimitBackoff);
      rethrow;
    }

    final result = range == ChartRange.day && !crypto
        ? _lastSession(points)
        : points;
    _cache[key] = (points: result, at: _now());
    return result;
  }

  // 1D changes every 5 minutes (a new bar); older ranges barely move within
  // an hour, so caching them longer saves most of the daily quota.
  static Duration _ttl(ChartRange range) => range == ChartRange.day
      ? const Duration(minutes: 5)
      : const Duration(hours: 1);

  /// Rejects instead of queueing: a queued request would arrive long after
  /// the user moved on, and still spend a credit. The cache makes hitting
  /// this rare in practice.
  void _checkRateLimit() {
    final now = _now();
    final until = _rateLimitedUntil;
    if (until != null && now.isBefore(until)) throw const RateLimitError();
    _sent.removeWhere((t) => now.difference(t) >= _window);
    if (_sent.length >= maxRequestsPerMinute) throw const RateLimitError();
  }

  /// 78 five-minute bars can reach back into yesterday's session (e.g. right
  /// after the open). Keep only the newest bar's day: a US session never
  /// crosses midnight UTC.
  static List<PricePoint> _lastSession(List<PricePoint> points) {
    if (points.isEmpty) return points;
    final last = points.last.time;
    return [
      for (final p in points)
        if (p.time.year == last.year &&
            p.time.month == last.month &&
            p.time.day == last.day)
          p,
    ];
  }
}
