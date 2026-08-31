import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_environment.dart';
import '../data/collaboration_repositories.dart';
import '../domain/collaboration_models.dart';

typedef MobileDeviceNameLoader = Future<String> Function();
typedef CurrentDeviceAuthorizationRegistrar =
    Future<ImDeviceAuthorization> Function({
      required String deviceName,
      required String platform,
    });

final currentMobileDeviceAuthorizationProvider =
    NotifierProvider<
      CurrentMobileDeviceAuthorizationController,
      ImDeviceAuthorization?
    >(CurrentMobileDeviceAuthorizationController.new);

final class CurrentMobileDeviceAuthorizationController
    extends Notifier<ImDeviceAuthorization?> {
  @override
  ImDeviceAuthorization? build() => null;

  void update(ImDeviceAuthorization value) => state = value;
}

final mobileDeviceNameLoaderProvider = Provider<MobileDeviceNameLoader>((ref) {
  return _loadMobileDeviceName;
});

final mobileDevicePlatformProvider = Provider<String>((ref) {
  return AppEnvironment.demoMode ? 'android' : Platform.operatingSystem;
});

final currentDeviceAuthorizationRegistrarProvider =
    Provider<CurrentDeviceAuthorizationRegistrar>((ref) {
      return ({required deviceName, required platform}) async {
        return ref
            .read(imRepositoryProvider)
            .registerDeviceAuthorization(
              deviceName: deviceName,
              platform: platform,
            );
      };
    });

final mobileDeviceAuthorizationCoordinatorProvider =
    Provider<MobileDeviceAuthorizationCoordinator>((ref) {
      return MobileDeviceAuthorizationCoordinator(ref);
    });

final class MobileDeviceAuthorizationCoordinator {
  MobileDeviceAuthorizationCoordinator(this._ref);

  final Ref _ref;
  Future<void>? _activeSynchronization;

  Future<void> synchronize() {
    final active = _activeSynchronization;
    if (active != null) return active;
    final synchronization = _synchronize();
    _activeSynchronization = synchronization;
    return synchronization.whenComplete(() {
      if (identical(_activeSynchronization, synchronization)) {
        _activeSynchronization = null;
      }
    });
  }

  Future<void> _synchronize() async {
    final name = await _ref.read(mobileDeviceNameLoaderProvider)();
    final current = await _ref.read(
      currentDeviceAuthorizationRegistrarProvider,
    )(deviceName: name, platform: _ref.read(mobileDevicePlatformProvider));
    _ref
        .read(currentMobileDeviceAuthorizationProvider.notifier)
        .update(current);
    _ref.invalidate(imDeviceAuthorizationsProvider);
  }
}

Future<String> _loadMobileDeviceName() async {
  if (AppEnvironment.demoMode) return 'Android 模拟器';
  if (!Platform.isAndroid) return '移动终端';
  final info = await DeviceInfoPlugin().androidInfo;
  final rawName = [
    info.brand,
    info.model,
  ].where((value) => value.trim().isNotEmpty).join(' ');
  final lowerName = rawName.toLowerCase();
  if (lowerName.contains('sdk_gphone') || lowerName.contains('generic_x86')) {
    return 'Android 模拟器';
  }
  return rawName.isEmpty ? 'Android 移动端' : rawName;
}
