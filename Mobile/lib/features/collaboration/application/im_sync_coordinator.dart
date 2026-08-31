import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_environment.dart';
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
  );
  ref.onDispose(coordinator.stop);
  return coordinator;
});

final class ImSyncCoordinator {
  ImSyncCoordinator(this._repository, {required this.onChanged});

  final ImRepository _repository;
  final void Function(ImSyncInvalidation) onChanged;
  bool _running = false;
  CancelToken? _activePull;
  Future<void>? _loop;

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

  Future<void> stop() async {
    _running = false;
    _activePull?.cancel('sync-stop');
    await _loop;
    _loop = null;
  }

  Future<void> _run() async {
    while (_running) {
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
        if (!CancelToken.isCancel(error) && _running) {
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      } catch (_) {
        if (_running) {
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      } finally {
        _activePull = null;
      }
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
