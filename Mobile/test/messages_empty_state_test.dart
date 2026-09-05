import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/auth/application/auth_controller.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/messages/presentation/messages_page.dart';

class _NoSession extends AuthController {
  @override
  Future<MobileSession?> build() async => null;
}

ImBootstrap fixture({bool includeGroup = false, bool unread = false}) =>
    ImBootstrap(
      currentMember: const ImMember(
        id: 'self',
        username: 'self',
        displayName: '我',
        isOnline: false,
      ),
      contacts: const [],
      conversations: [
        if (includeGroup)
          ImConversation(
            id: 'group',
            type: 'group',
            title: '验收测试群',
            preview: '群消息',
            updatedAt: null,
            unreadCount: unread ? 1 : 0,
            lastMessageSequence: 4,
            lastReadSequence: unread ? 3 : 4,
            unreadMentionSequences: unread ? [4] : [],
          ),
      ],
    );

void main() {
  const labels = ['全部', '未读', '@我', '群组'];
  const expected = ['暂无会话', '暂无未读消息', '暂无未读提及', '暂无群聊'];
  Future<void> mount(
    WidgetTester tester, {
    ProviderContainer? container,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final scope =
        container ??
        ProviderContainer(
          overrides: [
            authControllerProvider.overrideWith(_NoSession.new),
            imBootstrapProvider.overrideWith((ref) async => fixture()),
          ],
        );
    addTearDown(scope.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: scope,
        child: const MaterialApp(home: MessagesPage()),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (var tab = 0; tab < labels.length; tab++) {
    testWidgets('${labels[tab]} empty copy describes the selected filter', (
      tester,
    ) async {
      await mount(tester);
      await tester.tap(find.text(labels[tab]));
      await tester.pumpAndSettle();
      expect(find.text(expected[tab]), findsOneWidget);
      expect(find.text('没有匹配的会话'), findsNothing);
      if (tab != 0) expect(find.text('暂无会话'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets(
      '${labels[tab]} search miss restores filter copy when cleared',
      (tester) async {
        await mount(tester);
        await tester.tap(find.text(labels[tab]));
        await tester.enterText(find.byType(TextField), '没有这个人');
        await tester.pumpAndSettle();
        expect(find.text('没有匹配的会话'), findsOneWidget);
        await tester.enterText(find.byType(TextField), '   ');
        await tester.pumpAndSettle();
        expect(find.text(expected[tab]), findsOneWidget);
        expect(find.text('没有匹配的会话'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final tab in [1, 2]) {
    testWidgets(
      '${labels[tab]} read update empties only its filter, not the conversation',
      (tester) async {
        var unread = true;
        final container = ProviderContainer(
          overrides: [
            authControllerProvider.overrideWith(_NoSession.new),
            imBootstrapProvider.overrideWith(
              (ref) async => fixture(includeGroup: true, unread: unread),
            ),
          ],
        );
        await mount(tester, container: container);
        await tester.tap(find.text(labels[tab]));
        await tester.pumpAndSettle();
        expect(find.text('验收测试群'), findsOneWidget);
        unread = false;
        container.invalidate(imBootstrapProvider);
        await tester.pumpAndSettle();
        expect(find.text(expected[tab]), findsOneWidget);
        expect(find.text('暂无会话'), findsNothing);
        await tester.tap(find.text('全部'));
        await tester.pumpAndSettle();
        expect(find.text('验收测试群'), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
