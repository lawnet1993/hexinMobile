import 'dart:async';

/// Bounds *keep-alive* windows, never the history that a visible reader can use.
/// Releasing a lease permits auto-disposal; actual subscribers keep their data.
final class ImMessageWindowRetention {
  ImMessageWindowRetention({
    this.maxWindows = 32,
    this.maxMessages = 4096,
    this.retention = const Duration(minutes: 30),
    this.onChanged,
  }) : assert(maxWindows > 0),
       assert(maxMessages > 0);

  final int maxWindows;
  final int maxMessages;
  final Duration retention;
  final void Function(int windows, int messages)? onChanged;
  final _windows = <String, ImMessageWindowLease>{};
  bool _disposed = false;

  int get windowCount => _windows.length;
  int get messageCount =>
      _windows.values.fold(0, (sum, item) => sum + item._messages);

  ImMessageWindowLease acquire(String conversationId, void Function() close) {
    assert(!_disposed);
    // An older page-size provider can still have a real listener during the
    // transition. Closing only its keep-alive never invalidates that listener.
    _windows[conversationId]?.release();
    final lease = ImMessageWindowLease._(this, conversationId, close);
    _windows[conversationId] = lease;
    _trim();
    _notify();
    return lease;
  }

  void _touch(ImMessageWindowLease lease) {
    if (lease._released || !identical(_windows[lease._key], lease)) return;
    _windows.remove(lease._key);
    _windows[lease._key] = lease;
  }

  void _trim() {
    while (_windows.length > maxWindows || messageCount > maxMessages) {
      _windows.values.first.release();
    }
  }

  void _notify() {
    if (!_disposed) onChanged?.call(windowCount, messageCount);
  }

  void dispose() {
    _disposed = true;
    for (final lease in _windows.values.toList()) {
      lease.release();
    }
  }
}

final class ImMessageWindowLease {
  ImMessageWindowLease._(this._owner, this._key, this._close);
  final ImMessageWindowRetention _owner;
  final String _key;
  final void Function() _close;
  Timer? _expiry;
  int _messages = 0;
  bool _released = false;

  void loaded(int count) {
    if (_released) return;
    _messages = count;
    _owner._trim();
    _owner._notify();
  }

  void idle() {
    if (_released) return;
    _expiry?.cancel();
    _expiry = Timer(_owner.retention, release);
  }

  void resume() {
    if (_released) return;
    _expiry?.cancel();
    _expiry = null;
    _owner._touch(this);
  }

  void release() {
    if (_released) return;
    _released = true;
    _expiry?.cancel();
    if (identical(_owner._windows[_key], this)) _owner._windows.remove(_key);
    _close();
    _owner._notify();
  }
}
