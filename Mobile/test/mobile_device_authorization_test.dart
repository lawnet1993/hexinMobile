import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/auth/application/auth_controller.dart';
import 'package:hexing_terminal_mobile/features/collaboration/application/mobile_device_authorization_coordinator.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/profile/presentation/profile_page.dart';
import 'package:hexing_terminal_mobile/features/profile/presentation/settings_pages.dart';

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
      'realme RMX3366 · Android',
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
      'realme RMX3366 · Android',
    );
  });

  test('device summary settles immediately while collaboration is offline', () {
    expect(
      deviceAuthorizationSummary(
        const AsyncLoading<List<ImDeviceAuthorization>>(),
        currentDeviceId: 'android-device',
        syncState: ImRealtimeAvailability.unavailable,
      ),
      '暂时无法同步',
    );
  });

  test('device summary distinguishes connecting from unavailable data', () {
    expect(
      deviceAuthorizationSummary(
        const AsyncLoading<List<ImDeviceAuthorization>>(),
        currentDeviceId: 'android-device',
        syncState: ImRealtimeAvailability.connecting,
      ),
      '正在同步设备',
    );
    expect(
      deviceAuthorizationSummary(
        const AsyncData<List<ImDeviceAuthorization>>([]),
        currentDeviceId: 'android-device',
        syncState: ImRealtimeAvailability.unavailable,
      ),
      '暂时无法同步',
    );
  });

  testWidgets('login devices replaces the offline spinner with retry', (
    tester,
  ) async {
    final never = Completer<List<ImDeviceAuthorization>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_TestAuthController.new),
          imRealtimeAvailabilityProvider.overrideWithValue(
            ImRealtimeAvailability.unavailable,
          ),
          imDeviceAuthorizationsProvider.overrideWith((ref) => never.future),
        ],
        child: const MaterialApp(home: LoginDevicesPage()),
      ),
    );
    await tester.pump();

    expect(find.text('暂时无法同步设备'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('已授权设备'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('login devices keeps connecting distinct from offline', (
    tester,
  ) async {
    final never = Completer<List<ImDeviceAuthorization>>();
    addTearDown(() {
      if (!never.isCompleted) never.complete(const []);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_TestAuthController.new),
          imRealtimeAvailabilityProvider.overrideWithValue(
            ImRealtimeAvailability.connecting,
          ),
          imDeviceAuthorizationsProvider.overrideWith((ref) => never.future),
        ],
        child: const MaterialApp(home: LoginDevicesPage()),
      ),
    );
    await tester.pump();

    expect(find.text('正在同步设备'), findsOneWidget);
    expect(find.text('暂时无法同步设备'), findsNothing);
    expect(find.text('已授权设备'), findsNothing);
    expect(find.text('重试'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login devices labels a real authorization list', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_TestAuthController.new),
          imRealtimeAvailabilityProvider.overrideWithValue(
            ImRealtimeAvailability.unavailable,
          ),
          imDeviceAuthorizationsProvider.overrideWith(
            (ref) async => [
              _device(
                id: 'android-device',
                name: 'realme RMX3366',
                platform: 'android',
              ),
              _device(
                id: 'windows-device',
                name: 'Windows device',
                platform: 'windows',
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: LoginDevicesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('已授权设备'), findsOneWidget);
    expect(find.text('realme RMX3366'), findsOneWidget);
    expect(find.text('Windows 设备'), findsOneWidget);
    expect(find.text('Windows device'), findsNothing);
    expect(find.textContaining('windows ·'), findsNothing);
    expect(find.text('离线 · 显示缓存'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same-name device revoke confirmation identifies activity time', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_TestAuthController.new),
          imRealtimeAvailabilityProvider.overrideWithValue(
            ImRealtimeAvailability.available,
          ),
          imDeviceAuthorizationsProvider.overrideWith(
            (ref) async => [
              _device(
                id: 'windows-device-a',
                name: 'Windows device',
                platform: 'windows',
              ),
              _device(
                id: 'windows-device-b',
                name: 'Windows 设备',
                platform: 'windows',
              ),
            ],
          ),
        ],
        child: const MaterialApp(home: LoginDevicesPage()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('撤销').first);
    await tester.pumpAndSettle();

    expect(find.text('撤销设备授权'), findsOneWidget);
    expect(find.textContaining('撤销“Windows 设备”（最近活动'), findsOneWidget);
    expect(find.textContaining('windows-device'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

final class _TestAuthController extends AuthController {
  @override
  Future<MobileSession?> build() async => const MobileSession(
    accessToken: 'test-token',
    deviceId: 'android-device',
    userId: 'test-user',
    displayName: '测试用户',
    username: 'test.account',
    policySignatureKey: '',
    imApiUrl: '',
    oaApiUrl: '',
  );
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
