import 'dart:async';

import 'package:flutter/services.dart';

enum TunnelPhase {
  unavailable,
  disconnected,
  preparing,
  connecting,
  connected,
  reconnecting,
  stopping,
  failed,
}

enum TunnelStopReason { user, update, logout, shutdown }

final class TunnelStatus {
  const TunnelStatus({
    required this.phase,
    this.message,
    this.profileId = '',
    this.profileVersion = '',
    this.coreVersion = '',
    this.uploadBytes = 0,
    this.downloadBytes = 0,
  });

  final TunnelPhase phase;
  final String? message;
  final String profileId;
  final String profileVersion;
  final String coreVersion;
  final int uploadBytes;
  final int downloadBytes;

  bool get isConnected => phase == TunnelPhase.connected;
}

final class TunnelRuntimeIdentity {
  const TunnelRuntimeIdentity({
    this.platform = '',
    this.architecture = '',
    this.corePath = '',
    this.coreVersion = '',
    this.coreSha256 = '',
  });

  final String platform;
  final String architecture;
  final String corePath;
  final String coreVersion;
  final String coreSha256;
}

final class TunnelProfile {
  const TunnelProfile({
    required this.profileId,
    required this.profileVersion,
    required this.configPath,
    required this.configSha256,
    required this.corePath,
    required this.coreVersion,
    required this.coreSha256,
    required this.signatureKeyId,
    required this.signedPayload,
    required this.signature,
    required this.signatureAlgorithm,
    required this.displayName,
    required this.allowBackground,
  });

  final String profileId;
  final String profileVersion;
  final String configPath;
  final String configSha256;
  final String corePath;
  final String coreVersion;
  final String coreSha256;
  final String signatureKeyId;
  final String signedPayload;
  final String signature;
  final String signatureAlgorithm;
  final String displayName;
  final bool allowBackground;
}

final class SecureTunnel {
  SecureTunnel._();

  static final SecureTunnel instance = SecureTunnel._();
  static const _methods = MethodChannel('com.hexing.zhilian/secure_tunnel');
  static const _events = EventChannel(
    'com.hexing.zhilian/secure_tunnel/status',
  );
  static const _unavailable = TunnelStatus(
    phase: TunnelPhase.unavailable,
    message: '当前安装包未包含原生安全隧道插件',
  );

  static void registerWith() {}

  Stream<TunnelStatus> get statusStream => _events
      .receiveBroadcastStream()
      .where((event) => event is Map)
      .map((event) => _status(Map<Object?, Object?>.from(event as Map)))
      .handleError((_) {});

  Future<TunnelRuntimeIdentity> getRuntimeIdentity() async {
    try {
      final value = await _methods.invokeMapMethod<Object?, Object?>(
        'getRuntimeIdentity',
      );
      return TunnelRuntimeIdentity(
        platform: value?['platform']?.toString() ?? '',
        architecture: value?['architecture']?.toString() ?? '',
        corePath: value?['corePath']?.toString() ?? '',
        coreVersion: value?['coreVersion']?.toString() ?? '',
        coreSha256: value?['coreSha256']?.toString() ?? '',
      );
    } on MissingPluginException {
      return const TunnelRuntimeIdentity();
    }
  }

  Future<TunnelStatus> getStatus() async {
    try {
      final value = await _methods.invokeMapMethod<Object?, Object?>(
        'getStatus',
      );
      return value == null ? _unavailable : _status(value);
    } on MissingPluginException {
      return _unavailable;
    }
  }

  Future<bool> requestPermission() async {
    try {
      return await _methods.invokeMethod<bool>('requestPermission') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  Future<void> installProfile(TunnelProfile profile) =>
      _methods.invokeMethod('installProfile', <String, Object?>{
        'profileId': profile.profileId,
        'profileVersion': profile.profileVersion,
        'configPath': profile.configPath,
        'configSha256': profile.configSha256,
        'corePath': profile.corePath,
        'coreVersion': profile.coreVersion,
        'coreSha256': profile.coreSha256,
        'signatureKeyId': profile.signatureKeyId,
        'signedPayload': profile.signedPayload,
        'signature': profile.signature,
        'signatureAlgorithm': profile.signatureAlgorithm,
        'displayName': profile.displayName,
        'allowBackground': profile.allowBackground,
      });
  Future<void> start() => _methods.invokeMethod('start');
  Future<void> stop(TunnelStopReason reason) =>
      _methods.invokeMethod('stop', {'reason': reason.name});
  Future<void> rollback() => _methods.invokeMethod('rollback');

  static TunnelStatus _status(Map<Object?, Object?> value) => TunnelStatus(
    phase: TunnelPhase.values.firstWhere(
      (item) => item.name == value['phase']?.toString(),
      orElse: () => TunnelPhase.unavailable,
    ),
    message: value['message']?.toString(),
    profileId: value['profileId']?.toString() ?? '',
    profileVersion: value['profileVersion']?.toString() ?? '',
    coreVersion: value['coreVersion']?.toString() ?? '',
    uploadBytes: _integer(value['uploadBytes']),
    downloadBytes: _integer(value['downloadBytes']),
  );

  static int _integer(Object? value) => switch (value) {
    int result => result,
    num result => result.toInt(),
    _ => 0,
  };
}
