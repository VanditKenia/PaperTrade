/// Saving to local storage failed. Wraps Hive/disk errors so code above the
/// data layer can catch this one expected type without knowing about Hive.
class StorageError implements Exception {
  const StorageError(this.cause);

  final Object cause;

  @override
  String toString() => 'StorageError: $cause';
}
