import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/application/mobile_device_authorization_coordinator.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/profile/presentation/profile_page.dart';

void main() {
  test(
    'startup device authorization coalesces concurrent synchronization',
    () async {
      var nameLoads = 0;
      var registrations = 0;
      final container = ProviderContainer(
        overrides: [
          mobileDeviceNameLoaderProvider.overrideWithValue(() async {
            nameLoads += 1;
            await Future<void>.delayed(const Duration(milliseconds: 1));
            return 'realme RMX3366';
          }),
          mobileDevicePlatformProvider.overrideWithValue('android'),
          currentDeviceAuthorizationRegistrarProvider.overrideWithValue(({
            required deviceName,
            required platform,
          }) async {
            registrations += 1;
            expect(deviceName, 'realme RMX3366');
            expect(platform, 'android');
            return _device(
              id: 'android-device',
              name: deviceName,
              platform: platform,
            );
          }),
        ],
      );
      addTearDown(container.dispose);

      final coordinator = container.read(
        mobileDeviceAuthorizationCoordinatorProvider,
      );
      await Future.wait([coordinator.synchronize(), coordinator.synchronize()]);

      expect(nameLoads, 1);
      expect(registrations, 1);
      expect(
        container.read(currentMobileDeviceAuthorizationProvider)?.deviceName,
        'realme RMX3366',
      );
    },
  );

  test('device summary matches current id without case sensitivity', () {
    final devices = AsyncData<List<ImDeviceAuthorization>>([
      _device(
        id: 'ANDROID-DEVICE',
        name: 'realme RMX3366',
        platform: 'android',
      ),
      _device(
        id: 'windows-device',
        name: 'Windows device',
        platform: 'windows',
      ),
    ]);

    expect(
      deviceAuthorizationSummary(devices, currentDeviceId: 'android-device'),
      'realme RMX3366 · android',
    );
  });

  test('device summary never presents another authorization as current', () {
    final devices = AsyncData<List<ImDeviceAuthorization>>([
      _device(
        id: 'windows-device',
        name: 'Windows device',
        platform: 'windows',
      ),
    ]);

    expect(
      deviceAuthorizationSummary(devices, currentDeviceId: 'android-device'),
      '未登记当前设备',
    );
  });

  test('device summary prefers the authoritative current registration', () {
    final devices = AsyncData<List<ImDeviceAuthorization>>([
      _device(
        id: 'windows-device',
        name: 'Windows device',
        platform: 'windows',
      ),
    ]);

    expect(
      deviceAuthorizationSummary(
        devices,
        currentDeviceId: 'android-device',
        currentDevice: _device(
          id: 'android-device',
          name: 'realme RMX3366',
          platform: 'android',
        ),
      ),
      'realme RMX3366 · android',
    );
  });
}

ImDeviceAuthorization _device({
  required String id,
  required String name,
  required String platform,
}) => ImDeviceAuthorization(
  deviceId: id,
  deviceName: name,
  platform: platform,
  isAuthorized: true,
  authorizedAt: DateTime.utc(2026, 8, 31),
  lastSeenAt: DateTime.utc(2026, 8, 31),
  revokedAt: null,
);
