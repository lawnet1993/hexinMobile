import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/core/theme/app_theme.dart';
import 'package:hexing_terminal_mobile/features/auth/application/auth_controller.dart';
import 'package:hexing_terminal_mobile/features/auth/presentation/login_page.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/contacts/presentation/contacts_page.dart';
import 'package:hexing_terminal_mobile/features/messages/presentation/chat_page.dart';
import 'package:hexing_terminal_mobile/features/messages/presentation/conversation_detail_page.dart';
import 'package:hexing_terminal_mobile/features/messages/presentation/messages_page.dart';
import 'package:hexing_terminal_mobile/features/network/application/tunnel_controller.dart';
import 'package:hexing_terminal_mobile/features/profile/presentation/network_security_page.dart';
import 'package:hexing_terminal_mobile/features/profile/presentation/profile_page.dart';
import 'package:hexing_terminal_mobile/features/shell/presentation/mobile_shell.dart';
import 'package:hexing_terminal_mobile/features/todos/presentation/approval_detail_page.dart';
import 'package:hexing_terminal_mobile/features/todos/presentation/todos_page.dart';
import 'package:hexing_terminal_mobile/features/workbench/presentation/all_apps_page.dart';
import 'package:hexing_terminal_mobile/features/workbench/presentation/workbench_page.dart';
import 'package:hexing_terminal_mobile/features/workbench/data/managed_sites_repository.dart';
import 'package:secure_tunnel/secure_tunnel.dart';

const _captureKey = Key('mobile-design-capture');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await _loadFont('Microsoft YaHei', r'C:\Windows\Fonts\msyh.ttc');
    final flutterRoot =
        Platform.environment['FLUTTER_ROOT'] ??
        Platform.environment['FLUTTER_HOME'] ??
        r'C:\dev\flutter';
    await _loadFont(
      'MaterialIcons',
      '$flutterRoot\\bin\\cache\\artifacts\\material_fonts\\MaterialIcons-Regular.otf',
    );
  });

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(780, 1688);
    view.devicePixelRatio = 2;
  });

  tearDown(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  final cases = <({String name, Widget page, int? navigationIndex})>[
    (name: '01-login', page: const LoginPage(), navigationIndex: null),
    (name: '02-workbench', page: const WorkbenchPage(), navigationIndex: 0),
    (name: '03-all-apps', page: const AllAppsPage(), navigationIndex: null),
    (name: '04-messages', page: const MessagesPage(), navigationIndex: 1),
    (
      name: '05-chat',
      page: const ChatPage(conversationId: 'ops', enablePresence: false),
      navigationIndex: null,
    ),
    (name: '06-todos', page: const TodosPage(), navigationIndex: 2),
    (
      name: '07-approval-detail',
      page: const ApprovalDetailPage(approvalId: '1'),
      navigationIndex: null,
    ),
    (name: '08-contacts', page: const ContactsPage(), navigationIndex: 3),
    (name: '09-profile', page: const ProfilePage(), navigationIndex: 4),
    (
      name: '10-network-security',
      page: const NetworkSecurityPage(),
      navigationIndex: null,
    ),
    (
      name: '11-direct-detail',
      page: ConversationDetailPage(
        conversation: PreviewData.imBootstrap.conversations.firstWhere(
          (item) => item.id == 'tang',
        ),
        currentMember: PreviewData.imBootstrap.currentMember,
      ),
      navigationIndex: null,
    ),
    (
      name: '12-group-detail',
      page: ConversationDetailPage(
        conversation: PreviewData.imBootstrap.conversations.firstWhere(
          (item) => item.id == 'ops',
        ),
        currentMember: PreviewData.imBootstrap.currentMember,
      ),
      navigationIndex: null,
    ),
  ];

  for (final item in cases) {
    testWidgets('${item.name} matches the approved mobile composition', (
      tester,
    ) async {
      final page = item.navigationIndex == null
          ? item.page
          : Scaffold(
              body: item.page,
              bottomNavigationBar: MobileBottomNavigationBar(
                selectedIndex: item.navigationIndex!,
                unreadCount: PreviewData.imBootstrap.conversations.fold<int>(
                  0,
                  (total, conversation) => total + conversation.unreadCount,
                ),
                pendingApprovalCount: PreviewData.oaBootstrap.approvalRequests
                    .where((item) => item.operableTask != null)
                    .length,
                onDestinationSelected: (_) {},
              ),
            );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(_PreviewAuthController.new),
            oaBootstrapProvider.overrideWith(
              (ref) async => PreviewData.oaBootstrap,
            ),
            oaApplicationCatalogProvider.overrideWith(
              (ref) async => PreviewData.oaCatalog,
            ),
            oaApprovalRequestProvider.overrideWith(
              (ref, id) async => PreviewData.oaBootstrap.approvalRequests
                  .firstWhere((item) => item.id == id),
            ),
            imBootstrapProvider.overrideWith(
              (ref) async => PreviewData.imBootstrap,
            ),
            conversationMessagesProvider.overrideWith(
              (ref, id) async => PreviewData.messages,
            ),
            conversationMessageWindowProvider.overrideWith(
              (ref, key) async => PreviewData.messages,
            ),
            imVideoPreviewProvider.overrideWith((ref, key) async => null),
            conversationMembersProvider.overrideWith(
              (ref, id) async => PreviewData.conversationMembers(id),
            ),
            groupProfileProvider.overrideWith(
              (ref, id) async => PreviewData.groupProfile(id),
            ),
            groupManagersProvider.overrideWith(
              (ref, id) async => PreviewData.groupManagers(id),
            ),
            tunnelControllerProvider.overrideWith(_PreviewTunnelController.new),
            mobileClockProvider.overrideWithValue(DateTime(2026, 8, 13, 20)),
            managedSitesProvider.overrideWith((ref) async => const []),
          ],
          child: RepaintBoundary(
            key: _captureKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.lightWithFont('Microsoft YaHei'),
              home: page,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (item.name == '09-profile') {
        expect(find.text('密码与终端身份'), findsNothing);
        expect(find.text('提醒类型与方式'), findsNothing);
        expect(find.text('网络与安全'), findsOneWidget);
        expect(find.text('登录设备'), findsOneWidget);
        expect(find.text('外观与语言'), findsOneWidget);
      }
      await expectLater(
        find.byKey(_captureKey),
        matchesGoldenFile('goldens/${item.name}.png'),
      );
    });
  }
}

Future<void> _loadFont(String family, String path) async {
  final font = File(path);
  if (!font.existsSync()) return;
  final bytes = font.readAsBytesSync();
  await (FontLoader(family)..addFont(
        Future<ByteData>.value(
          bytes.buffer.asByteData(bytes.offsetInBytes, bytes.length),
        ),
      ))
      .load();
}

final class _PreviewAuthController extends AuthController {
  @override
  Future<MobileSession?> build() async => const MobileSession(
    accessToken: 'preview-token',
    deviceId: 'preview-device',
    userId: 'preview-user',
    displayName: '林晨',
    username: 'term.sh01',
    policySignatureKey: 'preview-key',
    imApiUrl: 'https://im.invalid',
    oaApiUrl: 'https://oa.invalid',
  );

  @override
  Future<SavedCredential?> savedCredential() async => null;
}

final class _PreviewTunnelController extends TunnelController {
  @override
  Future<TunnelConnectionState> build() async => const TunnelConnectionState(
    status: TunnelStatus(
      phase: TunnelPhase.connected,
      profileId: 'preview-profile',
      profileVersion: '2026.08.13',
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
      corePath: '/data/app/libmihomo.so',
    ),
  );

  @override
  Future<void> synchronize({bool requestPermission = true}) async {}
}
