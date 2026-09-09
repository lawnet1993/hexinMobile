import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/core/theme/app_theme.dart';
import 'package:hexing_terminal_mobile/core/updates/client_update_repository.dart';
import 'package:hexing_terminal_mobile/core/updates/client_update_sheet.dart';
import 'package:hexing_terminal_mobile/features/auth/application/auth_controller.dart';
import 'package:hexing_terminal_mobile/features/auth/presentation/login_page.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_member_presence.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
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
import 'package:hexing_terminal_mobile/shared/widgets/mobile_primitives.dart';
import 'package:hexing_terminal_mobile/shared/widgets/app_version_label.dart';
import 'package:secure_tunnel/secure_tunnel.dart';

import 'support/fixture_member_presence.dart';

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
    (
      name: '13-mandatory-update',
      page: const _MandatoryUpdatePreview(),
      navigationIndex: 0,
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
                pendingWorkCount: mobilePendingWorkCount(
                  PreviewData.oaBootstrap,
                ),
                onDestinationSelected: (_) {},
              ),
            );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appVersionProvider.overrideWith((ref) async => '1.0.1'),
            authControllerProvider.overrideWith(_PreviewAuthController.new),
            oaBootstrapProvider.overrideWith(
              (ref) async => PreviewData.oaBootstrap,
            ),
            oaSyncAvailabilityProvider.overrideWithValue(
              OaSyncAvailability.available,
            ),
            oaApplicationCatalogProvider.overrideWith(
              (ref) async => PreviewData.oaCatalog,
            ),
            oaApprovalRequestProvider.overrideWith(
              (ref, id) async => PreviewData.oaBootstrap.approvalRequests
                  .firstWhere((item) => item.id == id),
            ),
            imBootstrapProvider.overrideWith((ref) async {
              final source = PreviewData.imBootstrap;
              if (item.name != '05-chat') return source;
              // This golden is the existing, already-read chat composition.
              // Unread positioning has separate sequence-consistent tests.
              return ImBootstrap(
                currentMember: source.currentMember,
                contacts: source.contacts,
                permissions: source.permissions,
                config: source.config,
                conversations: source.conversations
                    .map(
                      (entry) => ImConversation(
                        id: entry.id,
                        type: entry.type,
                        title: entry.title,
                        preview: entry.preview,
                        updatedAt: entry.updatedAt,
                        unreadCount: 0,
                      ),
                    )
                    .toList(),
              );
            }),
            // Golden fixtures must not let an unconfigured real presence
            // request change the transport state of an otherwise online page.
            imRealtimeAvailabilityProvider.overrideWithValue(
              ImRealtimeAvailability.available,
            ),
            conversationPresenceProvider.overrideWith((ref, id) async {
              final conversation = PreviewData.imBootstrap.conversations
                  .firstWhere((item) => item.id == id);
              final members = PreviewData.conversationMembers(id);
              final peer = members
                  .where(
                    (item) =>
                        item.id != PreviewData.imBootstrap.currentMember.id,
                  )
                  .firstOrNull;
              return ImConversationPresence(
                conversationId: id,
                type: conversation.type,
                onlineMemberCount: members
                    .where((item) => item.isOnline)
                    .length,
                peerOnline: peer?.isOnline ?? false,
                serverTime: DateTime.utc(2026, 8, 13, 12),
              );
            }),
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
            conversationMemberPageProvider.overrideWith((ref, key) async {
              final members = PreviewData.conversationMembers(
                key.conversationId,
              );
              return ImMemberPage(
                items: members.take(key.pageSize).toList(growable: false),
                page: key.page,
                pageSize: key.pageSize,
                total: members.length,
              );
            }),
            groupProfileProvider.overrideWith(
              (ref, id) async => PreviewData.groupProfile(id),
            ),
            groupManagersProvider.overrideWith(
              (ref, id) async => PreviewData.groupManagers(id),
            ),
            imMemberPresenceProjectionProvider.overrideWith(
              () => FixtureMemberPresence([
                PreviewData.imBootstrap.currentMember,
                ...PreviewData.imBootstrap.contacts,
                for (final conversation
                    in PreviewData.imBootstrap.conversations)
                  ...PreviewData.conversationMembers(conversation.id),
              ]),
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
      if (item.name == '12-group-detail') {
        expect(find.text('3 位成员 · 3 人在线'), findsOneWidget);
        final avatars = tester.widgetList<InitialAvatar>(
          find.byType(InitialAvatar),
        );
        expect(avatars, hasLength(3));
        expect(avatars.every((avatar) => avatar.online == true), isTrue);
      }
      if (item.name == '09-profile') {
        expect(find.text('密码与终端身份'), findsNothing);
        expect(find.text('提醒类型与方式'), findsNothing);
        expect(find.text('term.sh01'), findsNothing);
        expect(
          tester.getSize(find.byKey(const Key('profile-summary-card'))).height,
          lessThanOrEqualTo(64),
        );
        expect(
          tester.getSize(find.byKey(const Key('profile-logout-entry'))).height,
          42,
        );
        expect(find.text('网络与安全'), findsNothing);
        expect(find.text('消息、审批与公告'), findsOneWidget);
        expect(find.text('登录设备'), findsOneWidget);
        expect(find.text('外观与语言'), findsOneWidget);
        expect(find.text('浅色'), findsOneWidget);
        expect(find.text('English'), findsNothing);
      }
      await expectLater(
        find.byKey(_captureKey),
        matchesGoldenFile('goldens/${item.name}.png'),
      );
    });
  }

  testWidgets('profile does not expose cached online state while offline', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_PreviewAuthController.new),
          imRealtimeAvailabilityProvider.overrideWithValue(
            ImRealtimeAvailability.unavailable,
          ),
          imBootstrapProvider.overrideWith(
            (ref) async => PreviewData.imBootstrap,
          ),
          tunnelControllerProvider.overrideWith(_PreviewTunnelController.new),
        ],
        child: const MaterialApp(home: ProfilePage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('状态未知'), findsNothing);
    expect(find.text('在线'), findsNothing);
  });

  testWidgets('profile summary stays actionable while member sync is offline', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_PreviewAuthController.new),
          imRealtimeAvailabilityProvider.overrideWithValue(
            ImRealtimeAvailability.unavailable,
          ),
          imBootstrapProvider.overrideWith(
            (ref) => Completer<ImBootstrap>().future,
          ),
          tunnelControllerProvider.overrideWith(_PreviewTunnelController.new),
        ],
        child: const MaterialApp(home: ProfilePage()),
      ),
    );
    await tester.pump();

    final summary = find.byKey(const Key('profile-summary-card'));
    expect(summary, findsOneWidget);
    final inkWell = tester.widget<InkWell>(
      find.descendant(of: summary, matching: find.byType(InkWell)),
    );
    expect(inkWell.onTap, isNotNull);
  });

  testWidgets('profile does not flash the account as a display name', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(
            _AccountLikeDisplayAuthController.new,
          ),
          imRealtimeAvailabilityProvider.overrideWithValue(
            ImRealtimeAvailability.connecting,
          ),
          imBootstrapProvider.overrideWith(
            (ref) => Completer<ImBootstrap>().future,
          ),
          tunnelControllerProvider.overrideWith(_PreviewTunnelController.new),
        ],
        child: const MaterialApp(home: ProfilePage()),
      ),
    );
    await tester.pump();

    expect(find.text('个人资料'), findsOneWidget);
    expect(find.text('laowang'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conversation details do not expose cached presence offline', (
    tester,
  ) async {
    final group = PreviewData.imBootstrap.conversations.firstWhere(
      (item) => item.id == 'ops',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imRealtimeAvailabilityProvider.overrideWithValue(
            ImRealtimeAvailability.unavailable,
          ),
          imBootstrapProvider.overrideWith(
            (ref) async => PreviewData.imBootstrap,
          ),
          conversationMembersProvider.overrideWith(
            (ref, id) async => PreviewData.conversationMembers(id),
          ),
          conversationMemberPageProvider.overrideWith((ref, key) async {
            final members = PreviewData.conversationMembers(key.conversationId);
            return ImMemberPage(
              items: members.take(key.pageSize).toList(growable: false),
              page: key.page,
              pageSize: key.pageSize,
              total: members.length,
            );
          }),
          groupProfileProvider.overrideWith(
            (ref, id) async => PreviewData.groupProfile(id),
          ),
          groupManagersProvider.overrideWith(
            (ref, id) async => PreviewData.groupManagers(id),
          ),
        ],
        child: MaterialApp(
          home: ConversationDetailPage(
            conversation: group,
            currentMember: PreviewData.imBootstrap.currentMember,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('3 位成员'), findsOneWidget);
    expect(find.textContaining('人在线'), findsNothing);

    final direct = PreviewData.imBootstrap.conversations.firstWhere(
      (item) => item.id == 'tang',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          imRealtimeAvailabilityProvider.overrideWithValue(
            ImRealtimeAvailability.unavailable,
          ),
          imBootstrapProvider.overrideWith(
            (ref) async => PreviewData.imBootstrap,
          ),
          conversationMembersProvider.overrideWith(
            (ref, id) async => PreviewData.conversationMembers(id),
          ),
        ],
        child: MaterialApp(
          home: ConversationDetailPage(
            conversation: direct,
            currentMember: PreviewData.imBootstrap.currentMember,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('状态未知'), findsOneWidget);
    expect(find.text('在线'), findsNothing);
  });
}

class _MandatoryUpdatePreview extends StatefulWidget {
  const _MandatoryUpdatePreview();

  @override
  State<_MandatoryUpdatePreview> createState() =>
      _MandatoryUpdatePreviewState();
}

class _MandatoryUpdatePreviewState extends State<_MandatoryUpdatePreview> {
  bool _shown = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shown) return;
    _shown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showClientUpdateSheet(
        context,
        info: const ClientUpdateInfo(
          hasPublishedVersion: true,
          updateAvailable: true,
          isMandatory: true,
          releaseId: 'release-golden',
          latestVersion: '1.0.81',
          packageUrl: 'https://example.test/mobile.apk',
          packageSize: 105706291,
          releaseNotes: '修复通知中心分页加载，优化消息页切回时的会话恢复。',
        ),
        onDownload: () async {},
      );
    });
  }

  @override
  Widget build(BuildContext context) => const WorkbenchPage();
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

final class _AccountLikeDisplayAuthController extends AuthController {
  @override
  Future<MobileSession?> build() async => const MobileSession(
    accessToken: 'preview-token',
    deviceId: 'preview-device',
    userId: 'preview-user',
    displayName: 'laowang',
    username: 'laowang',
    policySignatureKey: 'preview-key',
    imApiUrl: 'https://im.invalid',
    oaApiUrl: 'https://oa.invalid',
  );
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
