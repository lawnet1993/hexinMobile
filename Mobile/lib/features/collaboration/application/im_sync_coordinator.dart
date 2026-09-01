import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_environment.dart';
import '../../auth/application/auth_controller.dart';
import '../data/collaboration_repositories.dart';

final imSyncCoordinatorProvider = Provider<ImSyncCoordinator>((ref) {
  final coordinator = ImSyncCoordinator(
    ref.read(imRepositoryProvider),
    availabilityController: ref.read(
      imRealtimeAvailabilityControllerProvider.notifier,
    ),
    onChanged: (change) {
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
    onSessionInvalid: ({required bool replaced}) async {
      await ref
          .read(authControllerProvider.notifier)
          .terminateSession(
            message: replaced ? '当前移动端已在另一台设备登录，请重新登录' : '登录已失效或已到期，请重新登录',
          );
    },
  );
  ref.onDispose(coordinator.stop);
  return coordinator;
});

final class ImSyncCoordinator {
  ImSyncCoordinator(
    this._repository, {
    required this.availabilityController,
    required this.onChanged,
    this.onSessionInvalid,
  });

  final ImRepository _repository;
  final ImRealtimeAvailabilityController availabilityController;
  final void Function(ImSyncInvalidation) onChanged;
  final Future<void> Function({required bool replaced})? onSessionInvalid;
  bool _running = false;
  CancelToken? _activePull;
  Future<void>? _loop;
  bool _conversationProjectionReconcileRequested = false;
  final List<Completer<void>> _wakeWaiters = <Completer<void>>[];

  Future<void> start() async {
    if (_running || AppEnvironment.demoMode) return;
    _running = true;
    availabilityController.markConnecting();
    try {
      await _repository.refreshBootstrap();
      availabilityController.markAvailable();
      onChanged(const ImSyncInvalidation());
    } catch (_) {
      availabilityController.markUnavailable();
      // Cached projections remain usable while the network is unavailable.
    }
    _loop = _run();
  }

  void synchronizeNow({bool reconcileConversations = false}) {
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

  Future<void> stop() async {
    _running = false;
    availabilityController.markUnavailable();
    _activePull?.cancel('sync-stop');
    await _loop;
    _loop = null;
    _completeWakeWaiters();
  }

  Future<void> _run() async {
    while (_running) {
      var completedSyncAttempt = false;
      try {
        if (_conversationProjectionReconcileRequested) {
          _conversationProjectionReconcileRequested = false;
          final projectionChanged = await _repository
              .reconcileBootstrapFromBadges();
          if (projectionChanged) onChanged(const ImSyncInvalidation());
        }
        final delivered = await _repository.flushOutboxDetailed();
        if (delivered.conversationIds.isNotEmpty) {
          onChanged(
            ImSyncInvalidation(
              messageConversationIds: delivered.conversationIds,
            ),
          );
        }
        final cancelToken = CancelToken();
        _activePull = cancelToken;
        final result = await _repository.pullEvents(cancelToken: cancelToken);
        availabilityController.markAvailable();
        completedSyncAttempt = result.eventCount < 500;
        if (result.changed) {
          onChanged(
            ImSyncInvalidation(
              messageConversationIds: result.messageConversationIds,
              memberConversationIds: result.memberConversationIds,
              groupProfileConversationIds: result.groupProfileConversationIds,
            ),
          );
        } else if (result.eventCount == 0) {
          final projectionChanged = await _repository
              .reconcileBootstrapFromBadges();
          if (projectionChanged) onChanged(const ImSyncInvalidation());
        }
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        final body = error.response?.data;
        final code = body is Map
            ? (body['code'] ?? body['Code'])?.toString().trim().toLowerCase()
            : '';
        final replaced = status == 409 && code == 'session_replaced';
        if ((status == 401 || replaced) && _running) {
          _running = false;
          availabilityController.markUnavailable();
          await onSessionInvalid?.call(replaced: replaced);
        } else if (!CancelToken.isCancel(error) && _running) {
          availabilityController.markUnavailable();
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      } catch (_) {
        if (_running) {
          availabilityController.markUnavailable();
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      } finally {
        _activePull = null;
        if (completedSyncAttempt) _completeWakeWaiters();
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
