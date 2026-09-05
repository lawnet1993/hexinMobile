import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_environment.dart';
import '../../auth/application/auth_controller.dart';
import '../data/collaboration_repositories.dart';

final imSyncCoordinatorProvider = Provider<ImSyncCoordinator>((ref) {
  final coordinator = ImSyncCoordinator(
    ref.read(imRepositoryProvider),
    connectivityChanges: Connectivity().onConnectivityChanged,
    availabilityController: ref.read(
      imRealtimeAvailabilityControllerProvider.notifier,
    ),
    onChanged: (change) {
      if (!ref.mounted) return;
      ref.invalidate(imBootstrapProvider);
      ref.invalidate(imBadgeSummaryProvider);
      for (final conversationId in change.messageConversationIds) {
        ref.invalidate(conversationMessagesProvider(conversationId));
        ref.invalidate(conversationMessageRevisionProvider(conversationId));
      }
      for (final conversationId in change.memberConversationIds) {
        ref.invalidate(conversationMembersProvider(conversationId));
      }
      for (final conversationId in change.groupProfileConversationIds) {
        ref.invalidate(groupProfileProvider(conversationId));
      }
    },
    onSessionInvalid: (error) async {
      if (!ref.mounted) return false;
      return ref
          .read(authControllerProvider.notifier)
          .handleSessionFailure(error);
    },
  );
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

final class ImSyncCoordinator {
  ImSyncCoordinator(
    this._repository, {
    required this.availabilityController,
    required this.onChanged,
    this.onSessionInvalid,
    this.connectivityChanges,
  });

  final ImRepository _repository;
  final ImRealtimeAvailabilityController availabilityController;
  final void Function(ImSyncInvalidation) onChanged;
  final Future<bool> Function(DioException error)? onSessionInvalid;
  final Stream<List<ConnectivityResult>>? connectivityChanges;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  String? _networkSignature;
  bool _running = false;
  bool _disposed = false;
  int _generation = 0;
  CancelToken? _activePull;
  Future<void>? _loop;
  bool _conversationProjectionReconcileRequested = false;
  bool _networkOutboxResumeRequested = false;
  final List<Completer<void>> _wakeWaiters = <Completer<void>>[];

  Future<void> start() async {
    if (_disposed || _running || AppEnvironment.demoMode) return;
    _running = true;
    final generation = ++_generation;
    _networkSignature = null;
    _connectivitySubscription = connectivityChanges?.listen(
      (results) {
        if (!_isCurrent(generation)) return;
        final interfaces =
            results
                .where((result) => result != ConnectivityResult.none)
                .map((result) => result.name)
                .toSet()
                .toList()
              ..sort();
        final signature = interfaces.join(',');
        if (signature == _networkSignature) return;
        _networkSignature = signature;
        if (signature.isNotEmpty) {
          _networkOutboxResumeRequested = true;
          // A radio change is only a wake-up hint, never proof of server health.
          // Interrupt a stale long poll after offline recovery/transport change.
          synchronizeNow(reconcileConversations: true);
        }
      },
      onError: (Object _) {
        // Periodic retry and app-resume sync remain available if the OS stream
        // fails; connectivity must never log the user out or stop local caching.
      },
    );
    availabilityController.markConnecting();
    try {
      await _repository.refreshBootstrap();
      if (!_isCurrent(generation)) return;
      // Cold start may not receive an initial OS connectivity event.
      _networkOutboxResumeRequested = true;
      availabilityController.markAvailable();
      onChanged(const ImSyncInvalidation());
    } catch (_) {
      if (!_isCurrent(generation)) return;
      availabilityController.markUnavailable();
      // Cached projections remain usable while the network is unavailable.
    }
    if (_isCurrent(generation)) _loop = _run(generation);
  }

  void synchronizeNow({bool reconcileConversations = false}) {
    if (_disposed || !_running) return;
    if (reconcileConversations) {
      _conversationProjectionReconcileRequested = true;
    }
    _activePull?.cancel('sync-wakeup');
  }

  Future<void> synchronizeNowAndWait({
    bool reconcileConversations = false,
  }) async {
    if (!_running) return;
    if (reconcileConversations) {
      _conversationProjectionReconcileRequested = true;
    }
    final completer = Completer<void>();
    _wakeWaiters.add(completer);
    _activePull?.cancel('sync-wakeup');
    try {
      await completer.future.timeout(const Duration(seconds: 35));
    } on TimeoutException {
      _wakeWaiters.remove(completer);
    }
  }

  bool _isCurrent(int generation) =>
      !_disposed && _running && generation == _generation;

  /// Provider disposal must not publish state to other disposing providers.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(stop());
  }

  Future<void> stop() async {
    _running = false;
    ++_generation;
    final subscription = _connectivitySubscription;
    _connectivitySubscription = null;
    final loop = _loop;
    _loop = null;
    _activePull?.cancel('sync-stop');
    _activePull = null;
    _conversationProjectionReconcileRequested = false;
    _networkOutboxResumeRequested = false;
    _completeWakeWaiters();
    if (!_disposed) availabilityController.markUnavailable();
    // Capture old handles before awaiting: a concurrent start owns new ones.
    await subscription?.cancel();
    await loop;
  }

  Future<void> _run(int generation) async {
    var catchupProgressed = false;
    while (_isCurrent(generation)) {
      var completedSyncAttempt = false;
      try {
        if (_networkOutboxResumeRequested) {
          _networkOutboxResumeRequested = false;
          await _repository.resumeNetworkOutbox();
          if (!_isCurrent(generation)) return;
        }
        if (_conversationProjectionReconcileRequested) {
          _conversationProjectionReconcileRequested = false;
          final projectionChanged = await _repository
              .reconcileConversationIndex(force: true);
          if (!_isCurrent(generation)) return;
          if (projectionChanged) onChanged(const ImSyncInvalidation());
          // First drain events without another 25-second wait, then repair
          // announced bodies below. Preserve the full-500 event priority.
          catchupProgressed = true;
        }
        final delivered = await _repository.flushOutboxDetailed();
        if (!_isCurrent(generation)) return;
        if (delivered.conversationIds.isNotEmpty) {
          onChanged(
            ImSyncInvalidation(
              messageConversationIds: delivered.conversationIds,
            ),
          );
        }
        final cancelToken = CancelToken();
        _activePull = cancelToken;
        final result = await _repository.pullEvents(
          waitSeconds: catchupProgressed ? 0 : 25,
          cancelToken: cancelToken,
          onCommitted: (committed) {
            if (!_isCurrent(generation)) return;
            onChanged(
              ImSyncInvalidation(
                messageConversationIds: committed.messageConversationIds,
                memberConversationIds: committed.memberConversationIds,
                groupProfileConversationIds:
                    committed.groupProfileConversationIds,
              ),
            );
          },
        );
        if (!_isCurrent(generation)) return;
        // A full page is not proof that the backlog is drained. Probe the next
        // page without long-polling, including the exactly-500 boundary.
        catchupProgressed = result.eventCount >= 500;
        availabilityController.markAvailable();
        completedSyncAttempt = result.eventCount < 500;
        if (result.eventCount < 500) {
          final projectionChanged = await _repository
              .reconcileConversationIndex(cancelToken: cancelToken);
          if (!_isCurrent(generation)) return;
          if (projectionChanged) onChanged(const ImSyncInvalidation());
          final repaired = await _repository.repairAnnouncedMessageGaps(
            cancelToken: cancelToken,
          );
          if (!_isCurrent(generation)) return;
          catchupProgressed = repaired.progressed;
          if (repaired.changed.isNotEmpty) {
            onChanged(
              ImSyncInvalidation(messageConversationIds: repaired.changed),
            );
          }
        }
      } on DioException catch (error) {
        if (!_isCurrent(generation)) return;
        final status = error.response?.statusCode;
        final body = error.response?.data;
        final code = body is Map
            ? (body['code'] ?? body['Code'])?.toString().trim().toLowerCase()
            : '';
        final replaced = status == 409 && code == 'session_replaced';
        if (status == 401 || replaced) {
          final terminated = await onSessionInvalid?.call(error) ?? true;
          if (!_isCurrent(generation)) return;
          if (terminated) {
            unawaited(stop());
            return;
          } else {
            await Future<void>.delayed(const Duration(seconds: 3));
          }
        } else if (!CancelToken.isCancel(error)) {
          availabilityController.markUnavailable();
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      } catch (_) {
        if (_isCurrent(generation)) {
          availabilityController.markUnavailable();
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      } finally {
        if (_isCurrent(generation)) {
          _activePull = null;
          if (completedSyncAttempt) _completeWakeWaiters();
        }
      }
    }
  }

  void _completeWakeWaiters() {
    final waiters = List<Completer<void>>.of(_wakeWaiters);
    _wakeWaiters.clear();
    for (final completer in waiters) {
      if (!completer.isCompleted) completer.complete();
    }
  }
}

final class ImSyncInvalidation {
  const ImSyncInvalidation({
    this.messageConversationIds = const <String>{},
    this.memberConversationIds = const <String>{},
    this.groupProfileConversationIds = const <String>{},
  });

  final Set<String> messageConversationIds;
  final Set<String> memberConversationIds;
  final Set<String> groupProfileConversationIds;
}
