import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/config.dart';
import '../core/money.dart';
import '../core/throttle.dart';

final priceStreamServiceProvider = Provider<PriceStreamService>((ref) {
  final service = PriceStreamService(finnhubApiKey);
  ref.onDispose(service.dispose);
  return service;
});

/// Live trade prices from the Finnhub WebSocket (API_SPEC.md §3).
///
/// Keeps the latest price per symbol and publishes snapshots of all of them,
/// throttled to one every 500 ms. Reconnects with exponential backoff.
class PriceStreamService {
  PriceStreamService(this._apiKey, {WebSocketChannel Function(Uri)? connect})
    : _connect = connect ?? WebSocketChannel.connect;

  final String _apiKey;
  // WebSocketChannel.connect picks the browser or dart:io implementation,
  // so the same code runs on web and Android.
  final WebSocketChannel Function(Uri) _connect;

  static const throttleInterval = Duration(milliseconds: 500);
  static const maxSymbols = 50; // Finnhub free-tier limit

  final _sources = <String, Set<String>>{};
  final _symbols = <String>{}; // currently subscribed
  final _latest = <String, int>{};
  final _snapshots = StreamController<Map<String, int>>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _reconnectTimer;
  bool _wanted = false; // true between start() and stop()
  bool _connected = false;
  int _failures = 0;

  /// Latest price (cents) per symbol, at most one snapshot per 500 ms.
  Stream<Map<String, int>> get prices =>
      throttleLatest(_snapshots.stream, throttleInterval);

  void start() {
    if (_wanted) return;
    _wanted = true;
    _open();
  }

  /// Closes the socket (e.g. app in background) until [start] is called.
  void stop() {
    _wanted = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _close();
  }

  void dispose() {
    stop();
    _snapshots.close();
  }

  /// Sets the symbols one [source] (watchlist, an open detail screen…) wants.
  /// The socket subscribes to the union of all sources, so closing a detail
  /// screen doesn't unsubscribe a symbol the watchlist still shows.
  void setSymbols(Iterable<String> symbols, {String source = 'watchlist'}) {
    _sources[source] = symbols.toSet();
    final next = _sources.values
        .expand((s) => s)
        .toSet()
        .take(maxSymbols)
        .toSet();
    for (final s in _symbols.difference(next)) {
      _send('unsubscribe', s);
      _latest.remove(s);
    }
    for (final s in next.difference(_symbols)) {
      _send('subscribe', s);
    }
    _symbols
      ..clear()
      ..addAll(next);
  }

  Future<void> _open() async {
    // Contains the token: never log this URI.
    final uri = Uri(
      scheme: 'wss',
      host: 'ws.finnhub.io',
      queryParameters: {'token': _apiKey},
    );
    final channel = _connect(uri);
    _channel = channel;
    _sub = channel.stream.listen(
      _onMessage,
      onError: (_) => _reconnect(),
      onDone: _reconnect,
      cancelOnError: true,
    );
    try {
      await channel.ready;
    } catch (_) {
      if (identical(channel, _channel)) _reconnect();
      return;
    }
    if (!identical(channel, _channel)) return; // stopped or replaced meanwhile
    _connected = true;
    // Finnhub forgets subscriptions when a socket closes, so resend them all.
    for (final s in _symbols) {
      _send('subscribe', s);
    }
  }

  void _onMessage(dynamic raw) {
    // Reset backoff on a real message, not on connect: a server that accepts
    // and instantly drops us should still back off.
    _failures = 0;
    final prices = parseTrades(raw);
    prices.removeWhere((symbol, _) => !_symbols.contains(symbol));
    if (prices.isEmpty) return;
    _latest.addAll(prices);
    _snapshots.add(Map.unmodifiable(_latest));
  }

  void _reconnect() {
    _close();
    if (!_wanted || _reconnectTimer != null) return;
    // 1 s, 2 s, 4 s … capped at 30 s, so a long outage doesn't hammer the
    // server (or the battery).
    final delay = Duration(seconds: min(30, 1 << min(_failures, 5)));
    _failures++;
    if (kDebugMode) {
      debugPrint('Price stream disconnected; retrying in ${delay.inSeconds}s');
    }
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      if (_wanted) _open();
    });
  }

  void _close() {
    _connected = false;
    _sub?.cancel();
    _sub = null;
    _channel?.sink.close();
    _channel = null;
  }

  void _send(String type, String symbol) {
    if (!_connected) return; // sent on connect instead
    _channel?.sink.add(jsonEncode({'type': type, 'symbol': symbol}));
  }

  /// Parses one WebSocket message into the last price (cents) per symbol.
  /// Returns an empty map for pings, errors and anything malformed; never
  /// throws, so one bad message can't kill the stream.
  static Map<String, int> parseTrades(Object? raw) {
    if (raw is! String) return {};
    final Object? json;
    try {
      json = jsonDecode(raw);
    } on FormatException {
      return {};
    }
    if (json is! Map) return {};
    if (json['type'] == 'error' && kDebugMode) {
      debugPrint('Price stream error: ${json['msg']}');
    }
    final data = json['data'];
    if (json['type'] != 'trade' || data is! List) return {};

    final prices = <String, int>{};
    for (final trade in data) {
      if (trade is! Map) continue;
      final symbol = trade['s'];
      final price = trade['p'];
      if (symbol is String && price is num && price.isFinite && price > 0) {
        // Trades arrive in order, so a later one overwrites an earlier one.
        prices[symbol] = toCents(price.toDouble());
      }
    }
    return prices;
  }
}
