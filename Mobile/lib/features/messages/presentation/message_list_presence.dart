import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/storage/secure_session_store.dart';
import '../../auth/application/auth_controller.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/data/im_presence_projection.dart';
import '../../collaboration/domain/collaboration_models.dart';

typedef MessageListPresenceLoader = Future<ImConversationPresence?> Function(
  String id,
  MobileSession session,
  CancelToken cancellation,
);

final messageListPresenceLoaderProvider = Provider<MessageListPresenceLoader>(
  (ref) =>
      (id, session, cancellation) => ref
          .read(imRepositoryProvider)
          .conversationPresence(
            id,
            forSession: session,
            cancelToken: cancellation,
          ),
);
final messageListPresenceClockProvider = Provider<DateTime Function()>(
  (_) => DateTime.now,
);

typedef PresenceRowWrapper = Widget Function(String id, Widget child);

/// A single bounded poller owns visible direct rows. Never fetches the whole
/// directory, polls cached/offscreen rows, or assigns group counts to a person.
class MessageListPresence extends ConsumerStatefulWidget {
  const MessageListPresence({super.key, required this.builder});
  final Widget Function(BuildContext, PresenceRowWrapper, Set<String>) builder;

  @override
  ConsumerState<MessageListPresence> createState() =>
      _MessageListPresenceState();
}

class _MessageListPresenceState extends ConsumerState<MessageListPresence>
    with WidgetsBindingObserver {
  final _viewport = GlobalKey();
  final _targets = <String, BuildContext>{};
  final _nextDue = <String, DateTime>{};
  final _failed = <String>{};
  Timer? _timer;
  Timer? _debounce;
  CancelToken? _request;
  bool _routeVisible = false;
  bool _foreground = true;
  bool _viewportDirty = false;
  bool _frameScheduled = false;

  bool get _active => mounted && _routeVisible && _foreground;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final visible =
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.of(context)?.isCurrent ?? true);
    if (_routeVisible != visible) {
      _routeVisible = visible;
      _restart();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    _restart();
  }

  void _restart() {
    _timer?.cancel();
    _debounce?.cancel();
    _request?.cancel();
    _request = null;
    _nextDue.clear();
    if (!_active) return;
    _scheduleViewport();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _refresh());
  }

  void _register(String id, BuildContext row) {
    _targets[id] = row;
    _scheduleViewport();
  }

  void _unregister(String id, BuildContext row) {
    if (identical(_targets[id], row)) _targets.remove(id);
  }

  void _scheduleViewport() {
    if (!_active || _frameScheduled) return;
    _frameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _frameScheduled = false;
      if (!_active) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 120), _refresh);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Set<String> _visibleIds() {
    final viewport = _viewport.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.attached || !viewport.hasSize) {
      return {};
    }
    final rect = viewport.localToGlobal(Offset.zero) & viewport.size;
    return {
      for (final entry in _targets.entries)
        if (entry.value.mounted && _overlaps(entry.value, rect)) entry.key,
    };
  }

  bool _overlaps(BuildContext row, Rect viewport) {
    final box = row.findRenderObject();
    return box is RenderBox &&
        box.attached &&
        box.hasSize &&
        (box.localToGlobal(Offset.zero) & box.size).overlaps(viewport);
  }

  Future<void> _refresh() async {
    if (!_active || AppEnvironment.demoMode) return;
    if (_request != null) {
      _viewportDirty = true;
      return;
    }
    final session = ref.read(authControllerProvider).value;
    if (session == null) return;
    final now = ref.read(messageListPresenceClockProvider)();
    final visible = _visibleIds();
    final ids = visible
        .where((id) => !now.isBefore(_nextDue[id] ?? now))
        .toList();
    if (ids.isEmpty) return;
    _failed.removeWhere((id) => !_targets.containsKey(id));
    // Bound bookkeeping even when scrolling through thousands of conversations.
    _nextDue.removeWhere(
      (id, due) => !visible.contains(id) && !now.isBefore(due),
    );
    while (_nextDue.length > 128) {
      _nextDue.remove(_nextDue.keys.first);
    }
    final cancellation = CancelToken();
    _request = cancellation;
    final load = ref.read(messageListPresenceLoaderProvider);
    bool current() =>
        _active &&
        !cancellation.isCancelled &&
        identical(_request, cancellation) &&
        ref.read(authControllerProvider).value?.isSameSession(session) == true;
    var next = 0;
    Future<void> worker() async {
      while (current() && next < ids.length) {
        final id = ids[next++];
        if (!_visibleIds().contains(id)) continue;
        _nextDue[id] = now.add(const Duration(seconds: 25));
        try {
          final result = await load(id, session, cancellation);
          if (!current() || result == null) continue;
          if (result.conversationId != id || result.type != 'direct') {
            throw const FormatException('Invalid direct presence response');
          }
          ref
              .read(imPresenceProjectionProvider.notifier)
              .observe(session, result);
          ref
              .read(imRealtimeAvailabilityControllerProvider.notifier)
              .markAvailable();
          if (_failed.remove(id)) setState(() {});
        } on SessionChangedException {
          // The next session owns its own restart, status and requests.
        } catch (_) {
          if (current() && _failed.add(id)) setState(() {});
        }
      }
    }

    try {
      await Future.wait([worker(), worker()]);
    } finally {
      if (identical(_request, cancellation)) {
        _request = null;
        if (_viewportDirty) {
          _viewportDirty = false;
          _scheduleViewport();
        }
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _debounce?.cancel();
    _request?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authControllerProvider, (previous, next) {
      final before = previous?.value;
      final after = next.value;
      if (before == null
          ? after != null
          : after?.isSameSession(before) != true) {
        setState(_failed.clear);
        _restart();
      }
    });
    return NotificationListener<ScrollNotification>(
      onNotification: (_) {
        _scheduleViewport();
        return false;
      },
      child: SizedBox.expand(
        key: _viewport,
        child: widget.builder(
          context,
          (id, child) => _PresenceTarget(
            key: ValueKey(id),
            id: id,
            owner: this,
            child: child,
          ),
          Set.unmodifiable(_failed),
        ),
      ),
    );
  }
}

class _PresenceTarget extends StatefulWidget {
  const _PresenceTarget({
    super.key,
    required this.id,
    required this.owner,
    required this.child,
  });
  final String id;
  final _MessageListPresenceState owner;
  final Widget child;
  @override
  State<_PresenceTarget> createState() => _PresenceTargetState();
}

class _PresenceTargetState extends State<_PresenceTarget> {
  @override
  void initState() {
    super.initState();
    widget.owner._register(widget.id, context);
  }

  @override
  void didUpdateWidget(covariant _PresenceTarget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id || oldWidget.owner != widget.owner) {
      oldWidget.owner._unregister(oldWidget.id, context);
      widget.owner._register(widget.id, context);
    }
  }

  @override
  void dispose() {
    widget.owner._unregister(widget.id, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
