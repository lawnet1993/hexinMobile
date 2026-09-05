import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_environment.dart';
import '../data/collaboration_repositories.dart';

final oaCatalogSyncCoordinatorProvider = Provider<OaSyncCoordinator>((ref) {
  final availability = ref.read(oaSyncAvailabilityControllerProvider.notifier);
  final coordinator = OaSyncCoordinator(
    ref.read(oaRepositoryProvider),
    connectivityChanges: Connectivity().onConnectivityChanged,
    onChanged: () {
      ref.invalidate(oaBootstrapProvider);
      ref.invalidate(oaApplicationCatalogProvider);
      ref.invalidate(oaNotificationsProvider);
      ref.invalidate(oaNotificationPageProvider);
      ref.invalidate(oaAttendanceOverviewProvider);
      ref.invalidate(oaDraftsProvider);
      ref.invalidate(oaOutboxProvider);
      ref.invalidate(oaPendingNotificationReadsProvider);
    },
    onConnecting: availability.markConnecting,
    onAvailable: availability.markAvailable,
    onUnavailable: availability.markUnavailable,
    onRequestsChanged: (ids) {
      ref.read(oaApprovalRevisionsProvider.notifier).changed(ids);
    },
  );
  ref.onDispose(coordinator.stop);
  return coordinator;
});

final class OaSyncCoordinator {
  OaSyncCoordinator(
    this._repository, {
    required this.onChanged,
    required this.onConnecting,
    required this.onAvailable,
    required this.onUnavailable,
    required this.onRequestsChanged,
    this.connectivityChanges,
  });

  final OaRepository _repository;
  final void Function() onChanged;
  final void Function() onConnecting;
  final void Function() onAvailable;
  final void Function() onUnavailable;
  final void Function(Set<String>) onRequestsChanged;
  final Stream<List<ConnectivityResult>>? connectivityChanges;
  bool _running = false;
  int _generation = 0;
  bool _refreshRequested = false;
  bool _refreshing = false;
  bool _eventCatchUpRequested = false;
  bool _waitingLongPoll = false;
  String? _networkSignature;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  CancelToken? _activeOperation;
  Completer<void>? _startup;
  Completer<void>? _retryDelay;
  Timer? _retryTimer;
  Future<void>? _loop;

  Future<void> start() {
    if (_running) return _startup?.future ?? Future<void>.value();
    if (AppEnvironment.demoMode) return Future<void>.value();
    _running = true;
    final generation = ++_generation;
    _refreshRequested = true;
    _eventCatchUpRequested = false;
    _waitingLongPoll = false;
    _networkSignature = null;
    final startup = _startup = Completer<void>();
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
        final previous = _networkSignature;
        _networkSignature = signature;
        if (signature.isEmpty) {
          onUnavailable();
          _refreshRequested = true;
          _activeOperation?.cancel('oa-network-lost');
        } else if (previous != null || !_refreshing) {
          // An interface is a wake hint, not proof of service availability.
          _requestRefresh(transportChanged: true);
        }
      },
      onError: (Object _) {
        // Polling and app-resume recovery still work if the OS stream fails.
      },
    );
    _loop = _run(generation, startup);
    return startup.future;
  }

  bool _isCurrent(int generation) => _running && generation == _generation;

  void synchronizeNow() => _requestRefresh();

  /// A successful local mutation is a wake hint, not a replacement for the
  /// server event. Keep normal long polling, but do not wait for an old poll
  /// before reconciling the mutation's durable event and projections.
  void catchUpAfterMutation() {
    if (!_running || _eventCatchUpRequested) return;
    _eventCatchUpRequested = true;
    if (_waitingLongPoll) _activeOperation?.cancel('oa-local-mutation');
    _finishRetryDelay();
  }

  void _requestRefresh({bool transportChanged = false}) {
    if (!_running || (_refreshing && !transportChanged)) return;
    _refreshRequested = true;
    _activeOperation?.cancel('oa-sync-wakeup');
    _finishRetryDelay();
  }

  Future<void> stop() async {
    _running = false;
    _generation++;
    final loop = _loop;
    final subscription = _connectivitySubscription;
    _loop = null;
    _connectivitySubscription = null;
    _activeOperation?.cancel('oa-sync-stop');
    _finishRetryDelay();
    await subscription?.cancel();
    await loop;
  }

  void _finishRetryDelay() {
    _retryTimer?.cancel();
    _retryTimer = null;
    final pending = _retryDelay;
    _retryDelay = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  Future<void> _backoff() {
    final pending = _retryDelay = Completer<void>();
    _retryTimer = Timer(const Duration(seconds: 3), _finishRetryDelay);
    return pending.future;
  }

  Future<void> _run(int generation, Completer<void> startup) async {
    var catchUp = true;
    while (_isCurrent(generation)) {
      final cancelToken = CancelToken();
      _activeOperation = cancelToken;
      try {
        if (_refreshRequested) {
          _refreshRequested = false;
          _refreshing = true;
          onConnecting();
          await _repository.refreshWorkspace(cancelToken: cancelToken);
          if (!_isCurrent(generation) || cancelToken.isCancelled) continue;
          _refreshing = false;
          // Publish persisted projections before the available-state callback.
          onChanged();
          onAvailable();
          catchUp = true;
        }
        if (!startup.isCompleted) startup.complete();
        final delivered = await _repository.flushOutbox();
        if (!_isCurrent(generation) || cancelToken.isCancelled) continue;
        if (delivered > 0) {
          onChanged();
          catchUp = true;
        }
        final immediate = catchUp || _eventCatchUpRequested;
        _eventCatchUpRequested = false;
        _waitingLongPoll = !immediate;
        final result = await _repository.pullEvents(
          cancelToken: cancelToken,
          waitSeconds: immediate ? 0 : 20,
        );
        if (!_isCurrent(generation)) continue;
        _waitingLongPoll = false;
        // Cancellation may race with an already completed SQLite commit.
        // Publish that commit; the next zero-wait pull cannot replay its cursor.
        if (!cancelToken.isCancelled) onAvailable();
        catchUp = result.changed;
        if (result.changed) {
          onRequestsChanged(result.requestIds);
          onChanged();
        }
      } on DioException catch (error) {
        if (!CancelToken.isCancel(error) && _isCurrent(generation)) {
          cancelToken.cancel('oa-attempt-failed');
          _refreshing = false;
          _refreshRequested = true;
          onUnavailable();
          if (!startup.isCompleted) startup.complete();
          await _backoff();
        }
      } catch (_) {
        if (_isCurrent(generation)) {
          cancelToken.cancel('oa-attempt-failed');
          _refreshing = false;
          _refreshRequested = true;
          onUnavailable();
          if (!startup.isCompleted) startup.complete();
          await _backoff();
        }
      } finally {
        if (identical(_activeOperation, cancelToken)) {
          _activeOperation = null;
          _refreshing = false;
          _waitingLongPoll = false;
        }
      }
    }
    if (!startup.isCompleted) startup.complete();
  }
}
