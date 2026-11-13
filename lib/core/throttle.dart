import 'dart:async';

/// Emits at most one value per [interval]: the latest one received.
///
/// The first value starts a timer; values arriving before it fires just
/// replace the pending one, so 20 ticks in 400 ms become 1 emission. Nothing
/// is emitted when the source is quiet.
Stream<T> throttleLatest<T>(Stream<T> source, Duration interval) {
  late StreamController<T> controller;
  StreamSubscription<T>? sub;
  Timer? timer;
  late T latest;

  controller = StreamController<T>(
    onListen: () {
      sub = source.listen(
        (value) {
          latest = value;
          timer ??= Timer(interval, () {
            timer = null;
            controller.add(latest);
          });
        },
        onError: controller.addError,
        onDone: () {
          // Flush the pending value so the final state isn't lost.
          if (timer != null) {
            timer!.cancel();
            controller.add(latest);
          }
          controller.close();
        },
      );
    },
    onCancel: () {
      timer?.cancel();
      return sub?.cancel();
    },
  );
  return controller.stream;
}
