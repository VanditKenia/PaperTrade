import 'dart:async';
import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertrade/data/price_stream_service.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// In-memory stand-in for a WebSocket: tests push server messages into
/// [server] and read what the app sent from [sent].
class FakeChannel extends Fake implements WebSocketChannel {
  final server = StreamController<dynamic>();
  final sent = <Map<String, dynamic>>[];
  final _ready = Completer<void>();

  void open() => _ready.complete();
  void failToOpen() => _ready.completeError(Exception('refused'));

  @override
  Stream<dynamic> get stream => server.stream;

  @override
  Future<void> get ready => _ready.future;

  @override
  WebSocketSink get sink => _FakeSink(sent);
}

class _FakeSink extends Fake implements WebSocketSink {
  _FakeSink(this.sent);

  final List<Map<String, dynamic>> sent;

  @override
  void add(dynamic data) =>
      sent.add(jsonDecode(data as String) as Map<String, dynamic>);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}
}

String trade(List<(String, num)> trades) => jsonEncode({
  'type': 'trade',
  'data': [
    for (final (s, p) in trades) {'s': s, 'p': p, 't': 1, 'v': 1},
  ],
});

void main() {
  group('parseTrades', () {
    final parse = PriceStreamService.parseTrades;

    test('valid trade message → price in cents per symbol', () {
      expect(parse(trade([('AAPL', 189.43)])), {'AAPL': 18943});
    });

    test('multi-trade message keeps the latest per symbol', () {
      expect(parse(trade([('AAPL', 189.43), ('MSFT', 400), ('AAPL', 189.5)])), {
        'AAPL': 18950,
        'MSFT': 40000,
      });
    });

    test('ping is ignored', () {
      expect(parse('{"type":"ping"}'), isEmpty);
    });

    test('malformed input does not throw', () {
      for (final bad in <Object?>[
        'not json',
        '{"type":"trade"',
        '[]',
        '{"type":"trade","data":"oops"}',
        '{"type":"error","msg":"bad"}',
        null,
        42,
      ]) {
        expect(parse(bad), isEmpty, reason: '$bad');
      }
    });

    test('bad trades are skipped, good ones kept', () {
      final raw = jsonEncode({
        'type': 'trade',
        'data': [
          {'s': 'AAPL', 'p': 'NaN'},
          {'s': 'AAPL', 'p': -1},
          {'s': 'AAPL', 'p': 0},
          {'s': 7, 'p': 100},
          'junk',
          {'s': 'MSFT', 'p': 400.1},
        ],
      });
      expect(parse(raw), {'MSFT': 40010});
    });
  });

  group('connection', () {
    late List<FakeChannel> channels;
    late List<Uri> uris;
    late PriceStreamService service;

    setUp(() {
      channels = [];
      uris = [];
      service = PriceStreamService(
        'secret',
        connect: (uri) {
          uris.add(uri);
          final channel = FakeChannel();
          channels.add(channel);
          return channel;
        },
      );
    });

    test('connects to wss with the token and subscribes once open', () {
      fakeAsync((time) {
        service
          ..setSymbols(['AAPL', 'MSFT'])
          ..start();
        expect(uris.single.scheme, 'wss');
        expect(uris.single.queryParameters['token'], 'secret');
        expect(channels.single.sent, isEmpty); // not open yet

        channels.single.open();
        time.flushMicrotasks();
        expect(channels.single.sent, [
          {'type': 'subscribe', 'symbol': 'AAPL'},
          {'type': 'subscribe', 'symbol': 'MSFT'},
        ]);
      });
    });

    test('setSymbols sends only the difference', () {
      fakeAsync((time) {
        service
          ..setSymbols(['AAPL', 'MSFT'])
          ..start();
        channels.single.open();
        time.flushMicrotasks();
        channels.single.sent.clear();

        service.setSymbols(['MSFT', 'TSLA']);
        expect(channels.single.sent, [
          {'type': 'unsubscribe', 'symbol': 'AAPL'},
          {'type': 'subscribe', 'symbol': 'TSLA'},
        ]);
      });
    });

    test('emits throttled snapshots of subscribed symbols only', () {
      fakeAsync((time) {
        final snapshots = <Map<String, int>>[];
        service.prices.listen(snapshots.add);
        service
          ..setSymbols(['AAPL'])
          ..start();
        channels.single.open();
        time.flushMicrotasks();

        channels.single.server
          ..add(trade([('AAPL', 100)]))
          ..add('garbage')
          ..add(trade([('AAPL', 101), ('ZZZZ', 5)]));
        time.elapse(const Duration(milliseconds: 600));

        expect(snapshots, [
          {'AAPL': 10100},
        ]);
      });
    });

    test('reconnects with exponential backoff and re-subscribes', () {
      fakeAsync((time) {
        service
          ..setSymbols(['AAPL'])
          ..start();
        channels.single.failToOpen();
        time.flushMicrotasks();

        time.elapse(const Duration(milliseconds: 999));
        expect(channels, hasLength(1));
        time.elapse(const Duration(milliseconds: 1)); // 1 s
        expect(channels, hasLength(2));

        channels[1].failToOpen();
        time.flushMicrotasks();
        time.elapse(const Duration(milliseconds: 1999));
        expect(channels, hasLength(2));
        time.elapse(const Duration(milliseconds: 1)); // 2 s
        expect(channels, hasLength(3));

        channels[2].open();
        time.flushMicrotasks();
        expect(channels[2].sent, [
          {'type': 'subscribe', 'symbol': 'AAPL'},
        ]);

        // Server drops us after a real message → backoff restarts at 1 s.
        channels[2].server.add('{"type":"ping"}');
        channels[2].server.close();
        time.flushMicrotasks();
        time.elapse(const Duration(seconds: 1));
        expect(channels, hasLength(4));
      });
    });

    test('stop() closes and does not reconnect; start() reconnects', () {
      fakeAsync((time) {
        service.start();
        channels.single.open();
        time.flushMicrotasks();

        service.stop();
        time.elapse(const Duration(minutes: 1));
        expect(channels, hasLength(1));

        service.start();
        expect(channels, hasLength(2));
      });
    });
  });
}
