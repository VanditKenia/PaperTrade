/// Total portfolio value at one moment, for the Stats chart.
class ValueSnapshot {
  const ValueSnapshot({required this.time, required this.valueCents});

  final DateTime time;
  final int valueCents;
}

/// Rules for the list of value snapshots (oldest first).
abstract final class ValueHistory {
  /// Keeps storage bounded: at one per 5 minutes that's about a week of
  /// the app open nonstop, far more for normal use.
  static const maxSnapshots = 2000;

  /// Timed snapshots are at least this far apart. Trades always record.
  static const interval = Duration(minutes: 5);

  static bool isDue(List<ValueSnapshot> history, DateTime now) =>
      history.isEmpty || now.difference(history.last.time) >= interval;

  /// [history] plus [snapshot], dropping the oldest beyond [maxSnapshots].
  static List<ValueSnapshot> append(
    List<ValueSnapshot> history,
    ValueSnapshot snapshot,
  ) {
    final next = [...history, snapshot];
    return next.length > maxSnapshots
        ? next.sublist(next.length - maxSnapshots)
        : next;
  }
}
