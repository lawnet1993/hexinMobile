import 'dart:async';

import 'package:flutter/widgets.dart';

/// Bounded polling for a visible route, never an offstage tab or background app.
/// Owners call setVisible from didChangeDependencies (TickerMode + ModalRoute).
final class VisibleRefreshScheduler with WidgetsBindingObserver {
  VisibleRefreshScheduler(
    this.refresh, {
    this.interval = const Duration(seconds: 30),
  }) {
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  }

  final Future<void> Function() refresh;
  final Duration interval;
  Timer? _timer;
  bool _visible = false;
  bool _foreground = true;
  bool _busy = false;
  bool _disposed = false;

  void setVisible(bool visible) {
    if (_disposed || _visible == visible) return;
    _visible = visible;
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (_foreground == foreground) return;
    _foreground = foreground;
    _schedule();
  }

  void _schedule() {
    _timer?.cancel();
    if (_disposed || !_visible || !_foreground) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _request());
    WidgetsBinding.instance.ensureVisualUpdate();
    _timer = Timer.periodic(interval, (_) => _request());
  }

  Future<void> _request() async {
    if (_disposed || !_visible || !_foreground || _busy) return;
    _busy = true;
    try {
      await refresh();
    } catch (_) {
      // The owner exposes failed/unknown state. A later visible tick retries.
    } finally {
      _busy = false;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}
