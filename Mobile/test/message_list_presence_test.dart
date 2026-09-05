import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/auth/application/auth_controller.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_presence_projection.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/messages/presentation/message_list_presence.dart';
import 'package:hexing_terminal_mobile/features/messages/presentation/messages_page.dart';

const session = MobileSession(
  accessToken: 'fixture',
  deviceId: 'fixture',
  userId: 'self',
  username: 'self',
  displayName: 'Self',
  policySignatureKey: '',
  imApiUrl: '',
  oaApiUrl: '',
);

class _Auth extends AuthController {
  @override
  Future<MobileSession?> build() async => session;
  void replace(MobileSession? next) => state = AsyncData(next);
}

ImConversationPresence presence(String id, [bool online = true]) =>
    ImConversationPresence(
      conversationId: id,
      type: 'direct',
      peerOnline: online,
      onlineMemberCount: online ? 1 : 0,
    );

void main() {
  late ProviderContainer container;
  late DateTime now;
  late ValueNotifier<bool> visible;
  late ScrollController scroll;
  late Set<String> failed;
  var containerDisposed = false;
  setUp(() {
    containerDisposed = false;
    now = DateTime(2026, 9, 3);
    visible = ValueNotifier(true);
    scroll = ScrollController();
    failed = {};
    WidgetsBinding.instance.handleAppLifecycleStateChanged(
      AppLifecycleState.resumed,
    );
  });
  tearDown(() {
    if (!containerDisposed) container.dispose();
    visible.dispose();
    scroll.dispose();
  });
  Future<void> mount(
    WidgetTester tester,
    MessageListPresenceLoader load, {
    int count = 3,
    bool realPage = false,
  }) async {
    container = ProviderContainer(
      overrides: [
        authControllerProvider.overrideWith(_Auth.new),
        messageListPresenceLoaderProvider.overrideWithValue(load),
        messageListPresenceClockProvider.overrideWithValue(() => now),
        imBootstrapProvider.overrideWith(
          (_) async => const ImBootstrap(
            currentMember: ImMember(
              id: 'self',
              username: 'self',
              displayName: 'Self',
              isOnline: true,
            ),
            contacts: [],
            conversations: [
              ImConversation(
                id: 'direct',
                type: 'direct',
                title: 'Direct',
                preview: '',
                updatedAt: null,
                unreadCount: 0,
              ),
              ImConversation(
                id: 'group',
                type: 'group',
                title: 'Group',
                preview: '',
                updatedAt: null,
                unreadCount: 0,
              ),
            ],
          ),
        ),
        conversationMembersProvider.overrideWith((_, id) async => []),
      ],
    );
    await container.read(authControllerProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: visible,
            builder: (_, enabled, _) => TickerMode(
              enabled: enabled,
              child: realPage
                  ? const MessagesPage()
                  : Scaffold(
                      body: SizedBox(
                        height: 320,
                        child: MessageListPresence(
                          builder: (context, track, errors) {
                            failed = errors;
                            return ListView.builder(
                              controller: scroll,
                              itemExtent: 50,
                              itemCount: count,
                              itemBuilder: (_, i) => i == 0
                                  ? const Text('Group - never queried')
                                  : track(
                                      'direct-$i',
                                      SizedBox(
                                        height: 50,
                                        child: Text('Peer $i'),
                                      ),
                                    ),
                            );
                          },
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
  }

  Future<void> advance(WidgetTester tester, Duration by) async {
    now = now.add(by);
    await tester.pump(by);
    await tester.pump();
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    containerDisposed = true;
  }

  testWidgets('2000 conversations sample only viewport, not cache or groups', (
    tester,
  ) async {
    final calls = <String>[];
    var active = 0;
    var maximum = 0;
    await mount(tester, (id, _, _) async {
      calls.add(id);
      active++;
      if (active > maximum) maximum = active;
      await Future<void>.delayed(const Duration(milliseconds: 1));
      active--;
      return presence(id);
    }, count: 2000);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 5));
    }
    expect(calls.toSet(), {
      'direct-1',
      'direct-2',
      'direct-3',
      'direct-4',
      'direct-5',
      'direct-6',
    });
    expect(maximum, 2);
    scroll.jumpTo(2500);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 5));
    }
    expect(calls.skip(6).toSet(), {for (var i = 50; i <= 56; i++) 'direct-$i'});
    expect(calls, hasLength(13));
    await unmount(tester);
  });

  testWidgets('real message page polls direct rows and never group totals', (
    tester,
  ) async {
    final calls = <String>[];
    await mount(tester, (id, _, _) async {
      calls.add(id);
      return presence(id);
    }, realPage: true);
    expect(calls, ['direct']);
    await advance(tester, const Duration(seconds: 30));
    expect(calls, ['direct', 'direct']);
    await unmount(tester);
  });

  testWidgets('periodic visible refresh survives observation expiry', (
    tester,
  ) async {
    var online = true;
    var calls = 0;
    await mount(tester, (id, _, _) async {
      calls++;
      return presence(id, online);
    });
    for (var i = 0; i < 3; i++) {
      online = !online;
      await advance(tester, const Duration(seconds: 30));
      final value = container.read(imPresenceProjectionProvider)['direct-1'];
      expect(value?.fresh, true);
      expect(value?.value.peerOnline, online);
    }
    expect(calls, 8);
    await unmount(tester);
  });

  testWidgets(
    'background cancels in-flight work; late response cannot revive status',
    (tester) async {
      final late = Completer<ImConversationPresence?>();
      final tokens = <CancelToken>[];
      var calls = 0;
      await mount(tester, (id, _, token) {
        tokens.add(token);
        calls++;
        return calls <= 2 ? late.future : Future.value(presence(id, false));
      });
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      expect(tokens.every((token) => token.isCancelled), true);
      await advance(tester, const Duration(seconds: 90));
      expect(calls, 2);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(calls, 4);
      late.complete(presence('direct-1'));
      await tester.pump();
      expect(
        container
            .read(imPresenceProjectionProvider)['direct-1']
            ?.value
            .peerOnline,
        false,
      );
      await unmount(tester);
    },
  );

  testWidgets('offstage route stops polling and return refreshes immediately', (
    tester,
  ) async {
    var calls = 0;
    await mount(tester, (id, _, _) async {
      calls++;
      return presence(id);
    });
    visible.value = false;
    await tester.pump();
    await advance(tester, const Duration(seconds: 90));
    expect(calls, 2);
    visible.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(calls, 4);
    await unmount(tester);
  });

  testWidgets(
    'session rotation cancels old requests and rejects late online results',
    (tester) async {
      final late = Completer<ImConversationPresence?>();
      final tokens = <CancelToken>[];
      await mount(tester, (id, account, token) {
        tokens.add(token);
        return account.accessToken == 'fixture'
            ? late.future
            : Future.value(presence(id, false));
      });
      (container.read(authControllerProvider.notifier) as _Auth).replace(
        session.withTokens(accessToken: 'new-fixture'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(tokens.first.isCancelled, true);
      late.complete(presence('direct-1'));
      await tester.pump();
      expect(
        container
            .read(imPresenceProjectionProvider)['direct-1']
            ?.value
            .peerOnline,
        false,
      );
      await unmount(tester);
    },
  );

  testWidgets(
    'failure shows unknown locally, rate limits and recovers on next tick',
    (tester) async {
      var fail = true;
      var calls = 0;
      await mount(tester, (id, _, _) async {
        calls++;
        if (fail) throw StateError('offline fixture');
        return presence(id);
      });
      expect(failed, {'direct-1', 'direct-2'});
      await advance(tester, const Duration(seconds: 20));
      expect(calls, 2);
      fail = false;
      await advance(tester, const Duration(seconds: 10));
      expect(calls, 4);
      expect(failed, isEmpty);
      expect(container.read(authControllerProvider).value, session);
      await unmount(tester);
    },
  );

  testWidgets(
    'wrong identity or group response cannot mark a direct peer online',
    (tester) async {
      await mount(
        tester,
        (id, _, _) async => ImConversationPresence(
          conversationId: id,
          type: 'group',
          onlineMemberCount: 2000,
          peerOnline: true,
        ),
      );
      expect(container.read(imPresenceProjectionProvider), isEmpty);
      expect(failed, {'direct-1', 'direct-2'});
      await unmount(tester);
    },
  );

  testWidgets('covering bottom sheet pauses the list until it is dismissed', (
    tester,
  ) async {
    var calls = 0;
    await mount(tester, (id, _, _) async {
      calls++;
      return presence(id);
    });
    final routeContext = tester.element(find.byType(MessageListPresence));
    unawaited(
      showModalBottomSheet<void>(
        context: routeContext,
        builder: (_) =>
            const SizedBox(height: 100, child: Text('fixture sheet')),
      ),
    );
    await tester.pumpAndSettle();
    await advance(tester, const Duration(seconds: 90));
    expect(calls, 2);
    Navigator.of(routeContext).pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    expect(calls, 4);
    await unmount(tester);
  });

  testWidgets(
    'logout cancels the current sample and schedules no further work',
    (tester) async {
      final late = Completer<ImConversationPresence?>();
      final tokens = <CancelToken>[];
      await mount(tester, (id, _, token) {
        tokens.add(token);
        return late.future;
      });
      (container.read(authControllerProvider.notifier) as _Auth).replace(null);
      await tester.pump();
      expect(tokens.every((token) => token.isCancelled), true);
      late.complete(presence('direct-1'));
      await advance(tester, const Duration(seconds: 90));
      expect(tokens, hasLength(2));
      expect(container.read(imPresenceProjectionProvider), isEmpty);
      await unmount(tester);
    },
  );
}
