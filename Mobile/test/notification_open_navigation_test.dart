import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/notifications/presentation/notifications_page.dart';

void main() {
  test(
    'IM notification navigation does not submit a conversation read cursor',
    () async {
      final container = ProviderContainer(
        overrides: [
          imBootstrapProvider.overrideWith(
            (ref) => throw StateError('Must not read summary sequence'),
          ),
          imRepositoryProvider.overrideWith(
            (ref) => throw StateError('Must not mark unseen messages read'),
          ),
          oaRepositoryProvider.overrideWith(
            (ref) => throw StateError('IM is not an OA notification'),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(notificationReadSynchronizerProvider)(
        OaNotification.fromJson({
          'id': 'im-conversation:conversation-1',
          'targetKind': 'im_conversation',
          'targetId': 'conversation-1',
          'isRead': false,
        }),
      );
    },
  );

  testWidgets('notification opens its target before read sync completes', (
    tester,
  ) async {
    final readStarted = Completer<void>();
    final allowReadToFinish = Completer<void>();
    final notification = OaNotification(
      id: 'notification-pending-read',
      requestId: 'approval-pending-read',
      category: 'approval',
      type: 'approval.task.created',
      title: '待你审批：测试申请',
      body: '当前节点：部门负责人审批',
      importance: 'normal',
      action: 'view',
      isRead: false,
      readAt: null,
      createdAt: DateTime(2026, 9, 2, 8),
      targetKind: 'oa_approval',
      targetId: 'approval-pending-read',
    );
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, _) => const NotificationsPage()),
        GoRoute(
          path: '/approval/:id',
          builder: (_, state) =>
              Scaffold(body: Text('审批目标 ${state.pathParameters['id']}')),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          oaPendingNotificationReadsProvider.overrideWith((ref) async => 0),
          oaBootstrapProvider.overrideWith(
            (ref) async => PreviewData.oaBootstrap,
          ),
          oaNotificationsProvider.overrideWith((ref) async => [notification]),
          oaNotificationPageProvider.overrideWith(
            (ref, key) async => OaNotificationPage(
              items: key.unreadOnly || !notification.isRead
                  ? [notification]
                  : const [],
              nextCursor: null,
              hasMore: false,
            ),
          ),
          imBootstrapProvider.overrideWith(
            (ref) async => PreviewData.imBootstrap,
          ),
          pendingFriendApplicationsProvider.overrideWith(
            (ref) async => const [],
          ),
          notificationReadSynchronizerProvider.overrideWithValue((_) async {
            readStarted.complete();
            await allowReadToFinish.future;
          }),
        ],
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('notification-row-notification-pending-read')),
    );
    await tester.pumpAndSettle();

    expect(readStarted.isCompleted, isTrue);
    expect(find.text('审批目标 approval-pending-read'), findsOneWidget);
    expect(allowReadToFinish.isCompleted, isFalse);

    allowReadToFinish.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
