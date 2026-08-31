import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_environment.dart';
import '../data/collaboration_repositories.dart';

final oaCatalogSyncCoordinatorProvider = Provider<OaSyncCoordinator>((ref) {
  final coordinator = OaSyncCoordinator(
    ref.read(oaRepositoryProvider),
    onChanged: () {
      ref.invalidate(oaBootstrapProvider);
      ref.invalidate(oaApplicationCatalogProvider);
      ref.invalidate(oaNotificationsProvider);
      ref.invalidate(oaNotificationPageProvider);
      ref.invalidate(oaAttendanceOverviewProvider);
      ref.invalidate(oaDraftsProvider);
      ref.invalidate(oaOutboxProvider);
    },
  );
  ref.onDispose(coordinator.stop);
  return coordinator;
});

final class OaSyncCoordinator {
  OaSyncCoordinator(this._repository, {required this.onChanged});

  final OaRepository _repository;
  final void Function() onChanged;
  bool _running = false;
  CancelToken? _activePull;
  Future<void>? _loop;

  Future<void> start() async {
    if (_running || AppEnvironment.demoMode) return;
    _running = true;
    try {
      await _repository.refreshWorkspace();
      final delivered = await _repository.flushOutbox();
      if (delivered >= 0) onChanged();
    } catch (_) {
      // SQLite projections remain usable while the OA service is unavailable.
    }
    _loop = _run();
  }

  void synchronizeNow() {
    _activePull?.cancel('oa-sync-wakeup');
  }

  Future<void> stop() async {
    _running = false;
    _activePull?.cancel('oa-sync-stop');
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
