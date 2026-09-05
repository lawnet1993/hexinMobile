import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:secure_tunnel/secure_tunnel.dart';

import '../../../core/config/app_environment.dart';

import '../data/mobile_tunnel_repository.dart';
import 'tunnel_profile_verifier.dart';

final tunnelControllerProvider =
    AsyncNotifierProvider<TunnelController, TunnelConnectionState>(
      TunnelController.new,
    );

final class TunnelConnectionState {
  const TunnelConnectionState({
    required this.status,
    this.runtime,
    this.synchronizing = false,
    this.message,
  });

  final TunnelStatus status;
  final TunnelRuntimeIdentity? runtime;
  final bool synchronizing;
  final String? message;

  TunnelConnectionState copyWith({
    TunnelStatus? status,
    TunnelRuntimeIdentity? runtime,
    bool? synchronizing,
    String? message,
    bool clearMessage = false,
  }) => TunnelConnectionState(
    status: status ?? this.status,
    runtime: runtime ?? this.runtime,
    synchronizing: synchronizing ?? this.synchronizing,
    message: clearMessage ? null : message ?? this.message,
  );
}

class TunnelController extends AsyncNotifier<TunnelConnectionState> {
  StreamSubscription<TunnelStatus>? _subscription;
  bool _syncInProgress = false;

  @override
  Future<TunnelConnectionState> build() async {
    ref.onDispose(() => _subscription?.cancel());
    if (kIsWeb) {
      return const TunnelConnectionState(
        status: TunnelStatus(
          phase: TunnelPhase.unavailable,
          message: 'Web 预览不支持系统 VPN 隧道',
        ),
        message: 'Web 预览不支持系统 VPN 隧道',
      );
    }
    final runtime = await SecureTunnel.instance.getRuntimeIdentity();
    final status = await SecureTunnel.instance.getStatus();
    _subscription = SecureTunnel.instance.statusStream.listen(
      (next) {
        final current = state.value;
        if (current != null) state = AsyncData(current.copyWith(status: next));
      },
      onError: (Object error, StackTrace stackTrace) {
        final current = state.value;
        if (current != null) {
          state = AsyncData(current.copyWith(message: _message(error)));
        }
      },
    );
    return TunnelConnectionState(status: status, runtime: runtime);
  }

  Future<void> synchronize({bool requestPermission = true}) async {
    if (_syncInProgress) return;
    if (kIsWeb) {
      state = const AsyncData(
        TunnelConnectionState(
          status: TunnelStatus(
            phase: TunnelPhase.unavailable,
            message: 'Web 预览不支持系统 VPN 隧道',
          ),
          message: 'Web 预览不支持系统 VPN 隧道',
        ),
      );
      return;
    }
    _syncInProgress = true;
    final current = state.value;
    if (current != null) {
      state = AsyncData(
        current.copyWith(synchronizing: true, clearMessage: true),
      );
    }
    try {
      final runtime =
          current?.runtime ?? await SecureTunnel.instance.getRuntimeIdentity();
      _validateRuntime(runtime);
      final lookup = await ref
          .read(mobileTunnelRepositoryProvider)
          .fetchProfile(runtime);
      if (!lookup.isAuthorized) {
        throw const MobileTunnelException('当前终端没有安全连接权限');
      }
      final profile = lookup.profile;
      if (profile == null) {
        throw const MobileTunnelException('尚未发布可用的移动端连接策略');
      }
      final verified = await const TunnelProfileVerifier().verify(
        profile,
        runtime,
      );
      final latestStatus = await SecureTunnel.instance.getStatus();
      if (latestStatus.isConnected &&
          latestStatus.profileVersion == profile.profileVersion &&
          latestStatus.coreVersion == runtime.coreVersion) {
        _finish(latestStatus, runtime, '安全策略已是最新版本');
        return;
      }

      if (latestStatus.isConnected) {
        await SecureTunnel.instance.stop(TunnelStopReason.update);
        await _waitFor(
          (value) => value.phase == TunnelPhase.disconnected,
          timeout: const Duration(seconds: 15),
        );
      }
      final config = await _writeConfig(
        profile.profileVersion,
        verified.configBytes,
      );
      await SecureTunnel.instance.installProfile(
        TunnelProfile(
          profileId: profile.profileId,
          profileVersion: profile.profileVersion,
          configPath: config.path,
          configSha256: profile.configSha256,
          corePath: runtime.corePath,
          coreVersion: profile.coreVersion,
          coreSha256: profile.coreSha256,
          signatureKeyId: profile.signatureKeyId,
          signedPayload: profile.signedPayload,
          signature: profile.signature,
          signatureAlgorithm: profile.signatureAlgorithm,
          displayName: profile.displayName,
          allowBackground: profile.allowBackground,
        ),
      );
      if (requestPermission &&
          !await SecureTunnel.instance.requestPermission()) {
        throw const MobileTunnelException('需要允许系统 VPN 权限才能建立安全连接');
      }
      await SecureTunnel.instance.start();
      try {
        final connected = await _waitFor(
          (value) => value.isConnected,
          timeout: const Duration(seconds: 45),
        );
        _finish(connected, runtime, '安全策略同步完成');
      } catch (error) {
        await _rollbackAfterFailure();
        rethrow;
      }
    } catch (error, stackTrace) {
      final status = await SecureTunnel.instance.getStatus().catchError(
        (_) => const TunnelStatus(phase: TunnelPhase.failed),
      );
      final value = state.value;
      state = AsyncData(
        TunnelConnectionState(
          status: status,
          runtime: value?.runtime,
          message: _message(error),
        ),
      );
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      _syncInProgress = false;
    }
  }

  Future<void> _rollbackAfterFailure() async {
    try {
      await SecureTunnel.instance.rollback();
      await SecureTunnel.instance.start();
      await _waitFor(
        (value) => value.isConnected,
        timeout: const Duration(seconds: 30),
      );
    } catch (_) {
      // The original provisioning error remains the actionable failure.
    }
  }

  Future<File> _writeConfig(String version, List<int> bytes) async {
    final root = Directory(
      '${(await getApplicationSupportDirectory()).path}/'
      '${AppEnvironment.storageDirectoryName('managed-tunnel')}',
    );
    await root.create(recursive: true);
    final safeVersion = version.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    final target = File('${root.path}/config-$safeVersion.json');
    final temporary = File('${target.path}.installing');
    await temporary.writeAsBytes(bytes, flush: true);
    if (await target.exists()) await target.delete();
    return temporary.rename(target.path);
  }

  Future<TunnelStatus> _waitFor(
    bool Function(TunnelStatus status) predicate, {
    required Duration timeout,
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final status = await SecureTunnel.instance.getStatus();
      if (predicate(status)) return status;
      if (status.phase == TunnelPhase.failed) {
        throw MobileTunnelException(status.message ?? '安全连接启动失败');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw const MobileTunnelException('等待安全连接就绪超时');
  }

  void _finish(
    TunnelStatus status,
    TunnelRuntimeIdentity runtime,
    String message,
  ) {
    state = AsyncData(
      TunnelConnectionState(status: status, runtime: runtime, message: message),
    );
  }

  static void _validateRuntime(TunnelRuntimeIdentity value) {
    if (value.platform.isEmpty &&
        value.architecture.isEmpty &&
        value.coreVersion.isEmpty &&
        value.coreSha256.isEmpty &&
        value.corePath.isEmpty) {
      throw const MobileTunnelException('当前安装包未包含原生安全隧道');
    }
    if (value.corePath.isEmpty) {
      throw const MobileTunnelException('当前安装包未包含受信任的 mihomo 内核');
    }
    if (value.platform.isEmpty ||
        value.architecture.isEmpty ||
        value.coreVersion.isEmpty ||
        value.coreSha256.length != 64 ||
        value.corePath.isEmpty) {
      throw const MobileTunnelException('安装包内的 mihomo 内核身份无效');
    }
  }

  static String _message(Object error) {
    if (error is MobileTunnelException) return error.message;
    return '安全连接同步失败，请稍后重试';
  }
}
