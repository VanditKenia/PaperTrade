import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papertrade/core/throttle.dart';

void main() {
  const interval = Duration(milliseconds: 500);

  test('20 ticks in 400 ms → 1 emission with the latest value', () {
    fakeAsync((time) {
      final source = StreamController<int>();
      final out = <int>[];
      throttleLatest(source.stream, interval).listen(out.add);

      for (var i = 1; i <= 20; i++) {
        source.add(i);
        time.elapse(const Duration(milliseconds: 20));
      }
      time.elapse(const Duration(seconds: 1));

      expect(out, [20]);
    });
  });

  test('ticks across 1.2 s → 3 emissions', () {
    fakeAsync((time) {
      final source = StreamController<int>();
      final out = <int>[];
      throttleLatest(source.stream, interval).listen(out.add);

      for (var ms = 0; ms <= 1200; ms += 100) {
        source.add(ms);
        time.elapse(const Duration(milliseconds: 100));
      }
      time.elapse(const Duration(seconds: 1));

      expect(out, hasLength(3));
      expect(out.last, 1200);
    });
  });

  test('quiet source emits nothing', () {
    fakeAsync((time) {
      final out = <int>[];
      throttleLatest(StreamController<int>().stream, interval).listen(out.add);
      time.elapse(const Duration(seconds: 5));
      expect(out, isEmpty);
    });
  });

  test('pending value is flushed when the source closes', () {
    fakeAsync((time) {
      final source = StreamController<int>();
      final out = <int>[];
      throttleLatest(source.stream, interval).listen(out.add);
      source
        ..add(1)
        ..close();
      time.flushMicrotasks();
      expect(out, [1]);
    });
  });
}
