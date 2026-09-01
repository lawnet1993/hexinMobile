import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_environment.dart';
import '../../auth/application/auth_controller.dart';
import '../data/collaboration_repositories.dart';

final imSyncCoordinatorProvider = Provider<ImSyncCoordinator>((ref) {
  final coordinator = ImSyncCoordinator(
    ref.read(imRepositoryProvider),
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
    required this.onChanged,
    this.onSessionInvalid,
  });

  final ImRepository _repository;
  final void Function(ImSyncInvalidation) onChanged;
  final Future<void> Function({required bool replaced})? onSessionInvalid;
  bool _running = false;
  CancelToken? _activePull;
  Future<void>? _loop;
  final List<Completer<void>> _wakeWaiters = <Completer<void>>[];

  Future<void> start() async {
    if (_running || AppEnvironment.demoMode) return;
    _running = true;
    try {
      await _repository.refreshBootstrap();
      onChanged(const ImSyncInvalidation());
    } catch (_) {
      // Cached projections remain usable while the network is unavailable.
    }
    _loop = _run();
  }

  void synchronizeNow() {
    _activePull?.cancel('sync-wakeup');
  }

  Future<void> synchronizeNowAndWait() async {
    if (!_running) return;
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
    _activePull?.cancel('sync-stop');
    await _loop;
    _loop = null;
    _completeWakeWaiters();
  }

  Future<void> _run() async {
    while (_running) {
      var completedSyncAttempt = false;
      try {
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
        completedSyncAttempt = result.eventCount < 500;
        if (result.changed) {
          onChanged(
            ImSyncInvalidation(
              messageConversationIds: result.messageConversationIds,
              memberConversationIds: result.memberConversationIds,
              groupProfileConversationIds: result.groupProfileConversationIds,
            ),
          );
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
          await onSessionInvalid?.call(replaced: replaced);
        } else if (!CancelToken.isCancel(error) && _running) {
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      } catch (_) {
        if (_running) {
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
