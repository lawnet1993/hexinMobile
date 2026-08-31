import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_environment.dart';
import '../data/collaboration_repositories.dart';

final imSyncCoordinatorProvider = Provider<ImSyncCoordinator>((ref) {
  final coordinator = ImSyncCoordinator(
    ref.read(imRepositoryProvider),
    onChanged: () {
      ref.invalidate(imBootstrapProvider);
      ref.invalidate(imBadgeSummaryProvider);
      ref.invalidate(conversationMessagesProvider);
      ref.invalidate(conversationMessageWindowProvider);
      ref.invalidate(conversationMembersProvider);
      ref.invalidate(groupProfileProvider);
    },
  );
  ref.onDispose(coordinator.stop);
  return coordinator;
});

final class ImSyncCoordinator {
  ImSyncCoordinator(this._repository, {required this.onChanged});

  final ImRepository _repository;
  final void Function() onChanged;
  bool _running = false;
  CancelToken? _activePull;
  Future<void>? _loop;

  Future<void> start() async {
    if (_running || AppEnvironment.demoMode) return;
    _running = true;
    try {
      await _repository.refreshBootstrap();
      onChanged();
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
        final delivered = await _repository.flushOutbox();
        if (delivered > 0) onChanged();
        final cancelToken = CancelToken();
        _activePull = cancelToken;
        final result = await _repository.pullEvents(cancelToken: cancelToken);
        if (result.changed) onChanged();
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
