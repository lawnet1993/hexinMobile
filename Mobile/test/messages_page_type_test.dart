import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/messages/presentation/messages_page.dart';
import 'package:hexing_terminal_mobile/shared/widgets/mobile_primitives.dart';

void main() {
  test('bootstrap rejects unsupported conversation types', () {
    final bootstrap = ImBootstrap.fromJson({
      'currentMember': {'id': 'self'},
      'contacts': <Object?>[],
      'conversations': [
        {
          'id': 'direct-1',
          'type': 'direct',
          'title': '张三',
          'lastMessagePreview': '',
        },
        {
          'id': 'channel-1',
          'type': 'channel',
          'title': '不能伪装成单聊',
          'lastMessagePreview': '',
        },
      ],
    });

    expect(bootstrap.conversations, hasLength(1));
    expect(bootstrap.conversations.single.isDirect, isTrue);
  });

  const current = ImMember(
    id: 'self',
    username: 'self.user',
    displayName: '我',
    isOnline: true,
  );
  const peer = ImMember(
    id: 'peer',
    username: 'peer.user',
    displayName: '对方',
    isOnline: false,
  );

  test('单聊列表只显示对方姓名', () {
    const conversation = ImConversation(
      id: 'direct-1',
      type: 'direct',
      title: '我、对方',
      preview: '',
      updatedAt: null,
      unreadCount: 0,
    );

    expect(
      imConversationDisplayTitle(conversation, [current, peer], current.id),
      '对方',
    );
    expect(imDirectConversationPeer([current, peer], current.id), peer);
  });

  test('群聊列表保留群名称', () {
    const conversation = ImConversation(
      id: 'group-1',
      type: 'group',
      title: '产品研发群',
      preview: '',
      updatedAt: null,
      unreadCount: 0,
    );

    expect(
      imConversationDisplayTitle(conversation, [current, peer], current.id),
      '产品研发群',
    );
  });

  test('消息搜索可用终端账号命中对应单聊', () {
    const conversation = ImConversation(
      id: 'direct-1',
      type: 'direct',
      title: '我、对方',
      preview: '请确认接口文档',
      updatedAt: null,
      unreadCount: 0,
    );

    expect(
      imConversationMatchesQuery(
        conversation,
        [current, peer],
        current.id,
        'peer.user',
      ),
      isTrue,
    );
    expect(
      imConversationMatchesQuery(
        conversation,
        [current, peer],
        current.id,
        '不存在',
      ),
      isFalse,
    );
  });

  testWidgets('顶部搜索会展示终端账号对应的单聊', (tester) async {
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
          imBootstrapProvider.overrideWith(
            (ref) async => PreviewData.imBootstrap,
          ),
        ],
        child: const MaterialApp(home: MessagesPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NetworkIndicator), findsNothing);
    expect(find.byTooltip('我的收藏'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'term.gz01');
    await tester.pump();

    expect(find.text('唐泽'), findsOneWidget);
    expect(find.text('没有匹配的会话'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('发起会话弹层保持紧凑并隔离单聊群聊流程', (tester) async {
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
          imBootstrapProvider.overrideWith(
            (ref) async => PreviewData.imBootstrap,
          ),
        ],
        child: const MaterialApp(home: MessagesPage()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('发起会话'));
    await tester.pumpAndSettle();

    expect(find.text('发起会话'), findsOneWidget);
    expect(find.text('单聊'), findsOneWidget);
    final groupSegment = find.descendant(
      of: find.byType(SegmentedButton<bool>),
      matching: find.text('群聊'),
    );
    expect(groupSegment, findsOneWidget);
    expect(
      tester.getSize(find.byType(SegmentedButton<bool>)).height,
      lessThanOrEqualTo(40),
    );
    final sheetFields = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(TextField),
    );
    expect(tester.getSize(sheetFields).height, 38);
    expect(tester.takeException(), isNull);

    await tester.tap(groupSegment);
    await tester.pumpAndSettle();

    expect(find.text('群名称'), findsOneWidget);
    expect(find.text('创建群聊（0）'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(TextField),
      ),
      findsNWidgets(2),
    );
    expect(tester.takeException(), isNull);
  });
}
