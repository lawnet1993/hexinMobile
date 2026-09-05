import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/contacts/presentation/contacts_page.dart';

void main() {
  for (final existing in [true, false]) {
    for (final entry in ['row', 'avatar']) {
      testWidgets(
        '$entry opens one ${existing ? 'cached' : 'new'} route during keyboard hide',
        (tester) async {
          final fixture = await _mount(tester, existing: existing);
          final hide = Completer<void>();
          var hides = 0;
          _keyboard(tester, () {
            hides++;
            return hide.future;
          });
          final target = entry == 'row'
              ? find.text('AI-UAT Contact')
              : find.byWidgetPredicate(
                  (widget) =>
                      widget is Semantics &&
                      widget.properties.label == '联系AI-UAT Contact',
                );
          await tester.tap(target);
          await tester.tap(target);
          hide.complete();
          await tester.pumpAndSettle();
          expect(fixture.observer.chatPushes, 1);
          expect(hides, 1);
          expect(fixture.repository.calls, existing ? 0 : 1);
          fixture.router.pop();
          await tester.pumpAndSettle();
          expect(find.text('通讯录'), findsOneWidget);
          expect(find.text('chat:direct'), findsNothing);
          await tester.tap(find.text('AI-UAT Contact'));
          await tester.pumpAndSettle();
          expect(fixture.observer.chatPushes, 2);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('opening an existing route stays locked until it is popped', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    _keyboard(tester, () async {});
    final retainedCallback = tester
        .widget<ListTile>(find.byType(ListTile).last)
        .onTap!;
    retainedCallback();
    await tester.pumpAndSettle();
    retainedCallback();
    await tester.pumpAndSettle();
    expect(fixture.observer.chatPushes, 1);
    fixture.router.pop();
    await tester.pumpAndSettle();
    retainedCallback();
    await tester.pumpAndSettle();
    expect(fixture.observer.chatPushes, 2);
  });

  testWidgets('failed keyboard dismissal is handled and unlocks retry', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    var attempts = 0;
    _keyboard(tester, () async {
      if (++attempts == 1) throw PlatformException(code: 'test-only');
    });
    await tester.tap(find.text('AI-UAT Contact'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(fixture.observer.chatPushes, 0);
    await tester.tap(find.text('AI-UAT Contact'));
    await tester.pumpAndSettle();
    expect(fixture.observer.chatPushes, 1);
  });

  testWidgets('failed direct creation unlocks a later successful attempt', (
    tester,
  ) async {
    final fixture = await _mount(tester, existing: false);
    _keyboard(tester, () async {});
    fixture.repository.failNext = true;
    await tester.tap(find.text('AI-UAT Contact'));
    await tester.pumpAndSettle();
    expect(fixture.observer.chatPushes, 0);
    await tester.tap(find.text('AI-UAT Contact'));
    await tester.pumpAndSettle();
    expect(fixture.repository.calls, 2);
    expect(fixture.observer.chatPushes, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dispose during keyboard dismissal never opens a stale route', (
    tester,
  ) async {
    final fixture = await _mount(tester);
    final hide = Completer<void>();
    _keyboard(tester, () => hide.future);
    await tester.tap(find.text('AI-UAT Contact'));
    await tester.pumpWidget(const SizedBox());
    hide.complete();
    await tester.pump();
    expect(fixture.observer.chatPushes, 0);
    expect(tester.takeException(), isNull);
  });
}

void _keyboard(WidgetTester tester, Future<void> Function() hide) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.textInput,
    (call) async {
      if (call.method == 'TextInput.hide') await hide();
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.textInput,
      null,
    ),
  );
}

Future<({GoRouter router, _Observer observer, _Repository repository})> _mount(
  WidgetTester tester, {
  bool existing = true,
}) async {
  const peer = ImMember(
    id: 'peer',
    username: 'uat-peer',
    displayName: 'AI-UAT Contact',
    isOnline: false,
    isFriend: true,
    canStartDirect: true,
  );
  const current = ImMember(
    id: 'self',
    username: 'uat-self',
    displayName: 'AI-UAT Self',
    isOnline: false,
  );
  final observer = _Observer();
  final repository = _Repository();
  final router = GoRouter(
    observers: [observer],
    routes: [
      GoRoute(path: '/', builder: (_, _) => const ContactsPage(initialMode: 1)),
      GoRoute(
        path: '/chat/:id',
        name: 'chat',
        builder: (_, state) =>
            Scaffold(body: Text('chat:${state.pathParameters['id']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        imBootstrapProvider.overrideWith(
          (_) async => ImBootstrap(
            currentMember: current,
            contacts: const [peer],
            conversations: existing ? [_direct()] : const [],
          ),
        ),
        imDepartmentsProvider.overrideWith((_) async => const []),
        pendingFriendApplicationsProvider.overrideWith((_) async => const []),
        contactPresenceRefresherProvider.overrideWithValue(() async {}),
        contactConversationCreatorProvider.overrideWithValue(
          repository.createDirect,
        ),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  return (router: router, observer: observer, repository: repository);
}

ImConversation _direct() => ImConversation(
  id: 'direct',
  type: 'direct',
  title: 'AI-UAT Contact',
  preview: '',
  updatedAt: DateTime(2026, 9, 3),
  unreadCount: 0,
);

class _Observer extends NavigatorObserver {
  int chatPushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.settings.name == 'chat') chatPushes++;
    super.didPush(route, previousRoute);
  }
}

class _Repository {
  int calls = 0;
  bool failNext = false;
  Future<ImConversation> createDirect(String id) async {
    calls++;
    if (failNext) {
      failNext = false;
      throw StateError('test-only');
    }
    return _direct();
  }
}
