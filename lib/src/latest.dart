/// Runs a job on the newest value only: while one run is going, later values
/// replace each other, and the last one runs next. Words so far are translated
/// this way, so a slow phone skips stale ones instead of falling behind.
class LatestOnly<T> {
  LatestOnly(this.job);
  final Future<void> Function(T value) job;
  T? _pending;
  bool _busy = false, _hasPending = false;

  /// Whether a run is going.
  bool get busy => _busy;

  Future<void> offer(T value) async {
    if (_busy) {
      _pending = value;
      _hasPending = true;
      return;
    }
    _busy = true;
    try {
      await job(value);
    } catch (_) {
      // a failed run does not stop the next one
    } finally {
      _busy = false;
    }
    if (_hasPending) {
      final next = _pending as T;
      _hasPending = false;
      _pending = null;
      await offer(next);
    }
  }

  /// Drops a value waiting to run.
  void clear() {
    _hasPending = false;
    _pending = null;
  }
}
