import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/contacts/presentation/contacts_page.dart';
import 'package:hexing_terminal_mobile/features/messages/presentation/messages_page.dart';
import 'package:hexing_terminal_mobile/features/notifications/presentation/notifications_page.dart';
import 'package:hexing_terminal_mobile/features/todos/presentation/todos_page.dart';
import 'package:hexing_terminal_mobile/features/workbench/presentation/workbench_page.dart';

void main() {
  testWidgets('primary modules announce their own loading state', (
    tester,
  ) async {
    final scenarios = <({Widget page, List<Override> overrides, String label})>[
      (
        page: const WorkbenchPage(),
        overrides: [
          oaBootstrapProvider.overrideWith(
            (ref) => Completer<OaBootstrap>().future,
          ),
        ],
        label: '正在加载工作台',
      ),
      (
        page: const MessagesPage(),
        overrides: [
          imBootstrapProvider.overrideWith(
            (ref) => Completer<ImBootstrap>().future,
          ),
        ],
        label: '正在加载消息',
      ),
      (
        page: const TodosPage(),
        overrides: [
          oaBootstrapProvider.overrideWith(
            (ref) => Completer<OaBootstrap>().future,
          ),
        ],
        label: '正在加载待办',
      ),
      (
        page: const ContactsPage(),
        overrides: [
          imBootstrapProvider.overrideWith(
            (ref) => Completer<ImBootstrap>().future,
          ),
          pendingFriendApplicationsProvider.overrideWith(
            (ref) async => const [],
          ),
        ],
        label: '正在加载通讯录',
      ),
      (
        page: const NotificationsPage(),
        overrides: [
          oaNotificationPageProvider.overrideWith(
            (ref, key) => Completer<OaNotificationPage>().future,
          ),
          oaBootstrapProvider.overrideWith(
            (ref) => Completer<OaBootstrap>().future,
          ),
          pendingFriendApplicationsProvider.overrideWith(
            (ref) async => const [],
          ),
        ],
        label: '正在加载通知',
      ),
    ];

    for (final scenario in scenarios) {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: scenario.overrides,
          child: MaterialApp(home: scenario.page),
        ),
      );
      await tester.pump();

      expect(find.text(scenario.label), findsOneWidget);
      expect(find.bySemanticsLabel(scenario.label), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        tester.getSize(find.byType(CircularProgressIndicator)),
        const Size.square(20),
      );
      expect(tester.takeException(), isNull);
    }
  });
}
