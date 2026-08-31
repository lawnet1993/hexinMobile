import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/security/managed_security_repository.dart';
import 'package:hexing_terminal_mobile/core/theme/app_theme.dart';
import 'package:hexing_terminal_mobile/features/network/application/tunnel_controller.dart';
import 'package:hexing_terminal_mobile/features/profile/presentation/network_security_page.dart';
import 'package:secure_tunnel/secure_tunnel.dart';

void main() {
  testWidgets('unavailable tunnel uses compact user-facing diagnostics', (
    tester,
  ) async {
    final view = tester.view;
    view.physicalSize = const Size(390, 844);
    view.devicePixelRatio = 1;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tunnelControllerProvider.overrideWith(
            _UnavailableTunnelController.new,
          ),
          managedPolicyStatusProvider.overrideWith(
            (ref) async => ManagedPolicyStatus(
              policyVersion: 'prod-2026.08.20.001',
              publishedAt: DateTime(2026, 8, 20),
              enabled: true,
              signatureVerified: true,
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const NetworkSecurityPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('安全连接不可用'), findsOneWidget);
    expect(find.text('当前安装包未包含移动端安全组件'), findsOneWidget);
    expect(find.text('安全组件'), findsOneWidget);
    expect(find.text('未安装'), findsOneWidget);
    expect(find.text('运行环境'), findsOneWidget);
    expect(find.text('android · arm64-v8a'), findsOneWidget);

    expect(find.textContaining('mihomo'), findsNothing);
    expect(find.text('当前设备不支持安全连接'), findsNothing);
    expect(find.text('策略标识'), findsNothing);
    expect(find.text('策略版本'), findsNothing);
    expect(find.text('上传 / 下载'), findsNothing);

    final statusCard = tester.getSize(
      find.byKey(const Key('network-security-status-card')),
    );
    expect(statusCard.height, lessThanOrEqualTo(190));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'connected tunnel keeps diagnostics without implementation name',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            tunnelControllerProvider.overrideWith(
              _ConnectedTunnelController.new,
            ),
            managedPolicyStatusProvider.overrideWith(
              (ref) async => ManagedPolicyStatus(
                policyVersion: 'prod-2026.08.20.001',
                publishedAt: DateTime(2026, 8, 20),
                enabled: true,
                signatureVerified: true,
              ),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.light,
            home: const NetworkSecurityPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('安全连接正常'), findsOneWidget);
      expect(find.text('组件版本'), findsOneWidget);
      expect(find.text('1.19.12'), findsOneWidget);
      expect(find.textContaining('mihomo'), findsNothing);
      expect(find.text('策略标识'), findsOneWidget);
      expect(find.text('上传 / 下载'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

final class _UnavailableTunnelController extends TunnelController {
  @override
  Future<TunnelConnectionState> build() async => const TunnelConnectionState(
    status: TunnelStatus(phase: TunnelPhase.unavailable),
    runtime: TunnelRuntimeIdentity(
      platform: 'android',
      architecture: 'arm64-v8a',
      coreVersion: '',
      coreSha256: '',
      corePath: '',
    ),
    message: '当前安装包未包含受信任的 mihomo 内核',
  );

  @override
  Future<void> synchronize({bool requestPermission = true}) async {}
}

final class _ConnectedTunnelController extends TunnelController {
  @override
  Future<TunnelConnectionState> build() async => const TunnelConnectionState(
    status: TunnelStatus(
      phase: TunnelPhase.connected,
      profileId: 'mobile-prod',
      profileVersion: '2026.08.20',
      coreVersion: 'mihomo-1.19.12',
      uploadBytes: 1024,
      downloadBytes: 4096,
    ),
    runtime: TunnelRuntimeIdentity(
      platform: 'android',
      architecture: 'arm64-v8a',
      coreVersion: 'mihomo-1.19.12',
      coreSha256:
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
      corePath: '/data/app/libsecure-tunnel.so',
    ),
  );

  @override
  Future<void> synchronize({bool requestPermission = true}) async {}
}
