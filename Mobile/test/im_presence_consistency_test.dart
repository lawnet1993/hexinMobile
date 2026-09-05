import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/auth/application/auth_controller.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_presence_projection.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_member_presence.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/messages/presentation/messages_page.dart';
import 'package:hexing_terminal_mobile/features/messages/presentation/message_list_presence.dart';
import 'package:hexing_terminal_mobile/features/contacts/presentation/contacts_page.dart';
import 'package:hexing_terminal_mobile/shared/widgets/mobile_primitives.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const self = ImMember(
  id: 'self',
  username: 'self',
  displayName: '我',
  isOnline: true,
);
const oldPeer = ImMember(
  id: 'peer',
  username: 'peer',
  displayName: '对方',
  isOnline: true,
);
const currentPeer = ImMember(
  id: 'peer',
  username: 'peer',
  displayName: '对方',
  isOnline: false,
);
const conversation = ImConversation(
  id: 'direct',
  type: 'direct',
  title: '我、对方',
  preview: '',
  updatedAt: null,
  unreadCount: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  testWidgets('one member observation follows list to contacts and expires without per-row HTTP', (tester) async {
    var presenceRequests = 0;
    final container = ProviderContainer(overrides: [
      authControllerProvider.overrideWith(_FixtureAuth.new),
      imBootstrapProvider.overrideWith((ref) async => const ImBootstrap(
        currentMember: self, contacts: [oldPeer], conversations: [conversation],
      )),
      imDepartmentsProvider.overrideWith((ref) async => []),
      pendingFriendApplicationsProvider.overrideWith((ref) async => []),
      contactPresenceRefresherProvider.overrideWithValue(() async {}),
      conversationMembersProvider.overrideWith((ref, id) async => [self, oldPeer]),
      conversationPresenceProvider.overrideWith((ref, id) async {
        presenceRequests++;
        return _presence(true);
      }),
      messageListPresenceLoaderProvider.overrideWithValue((_, _, _) async => null),
    ]);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: const MaterialApp(home: MessagesPage())));
    await tester.pumpAndSettle();
    InitialAvatar avatar() => tester.widget<InitialAvatar>(find.byKey(const ValueKey('message-direct-avatar-direct')));
    expect(avatar().online, isNull);
    final projection = container.read(imMemberPresenceProjectionProvider.notifier);
    final delayedDirectory = projection.beginRequest();
    projection.observe(_session, projection.beginRequest(), [currentPeer]);
    await tester.pump();
    expect(avatar().online, false);
    projection.observe(_session, delayedDirectory, [oldPeer]);
    await tester.pump();
    expect(avatar().online, false);
    await tester.pumpWidget(UncontrolledProviderScope(container: container,
      child: const MaterialApp(home: ContactsPage())));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(ExpansionTile).first);
    await tester.pumpAndSettle();
    final peerTile = find.ancestor(of: find.text('对方'), matching: find.byType(ListTile));
    expect(find.descendant(of: peerTile, matching: find.text('离线')), findsOneWidget);
    projection.observe(_session, projection.beginRequest(), [ImMember(
      id: 'peer', username: 'peer', displayName: '对方', isOnline: false,
      lastSeenAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    )]);
    await tester.pump();
    expect(find.descendant(of: peerTile, matching: find.text('离线')), findsOneWidget);
    expect(find.textContaining('01-01'), findsNothing);
    projection.observe(_session, projection.beginRequest(), [oldPeer]);
    await tester.pump();
    expect(find.descendant(of: peerTile, matching: find.text('在线')), findsOneWidget);
    await tester.pump(const Duration(seconds: 61));
    await tester.pumpAndSettle();
    expect(find.descendant(of: peerTile, matching: find.text('状态未知')), findsOneWidget);
    expect(presenceRequests, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'directory and member cache alone do not establish current presence',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            imBootstrapProvider.overrideWith(
              (ref) async => const ImBootstrap(
                currentMember: self,
                contacts: [currentPeer],
                conversations: [conversation],
              ),
            ),
            conversationMembersProvider.overrideWith(
              (ref, id) async => [self, oldPeer],
            ),
          ],
          child: const MaterialApp(home: MessagesPage()),
        ),
      );
      await tester.pumpAndSettle();
      final semantics = tester.widget<Semantics>(
        find.byKey(const ValueKey('message-conversation-semantics-direct')),
      );
      expect(semantics.properties.label, '单聊，状态未知');
      final avatar = tester.widget<InitialAvatar>(
        find.byKey(const ValueKey('message-direct-avatar-direct')),
      );
      expect(avatar.online, isNull);
    },
  );

  testWidgets(
    'shared live observation updates row, expires and recovers without HTTP per row',
    (tester) async {
      var requests = 0;
      final container = ProviderContainer(
        overrides: [
          authControllerProvider.overrideWith(_FixtureAuth.new),
          imBootstrapProvider.overrideWith(
            (ref) async => const ImBootstrap(
              currentMember: self,
              contacts: [oldPeer],
              conversations: [conversation],
            ),
          ),
          conversationMembersProvider.overrideWith(
            (ref, id) async => [self, oldPeer],
          ),
          conversationPresenceProvider.overrideWith((ref, id) async {
            requests++;
            return _presence(true);
          }),
          // This test owns projection samples; viewport polling has its own tests.
          messageListPresenceLoaderProvider.overrideWithValue((_, _, _) async => null),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: MessagesPage()),
        ),
      );
      await tester.pumpAndSettle();
      final projection = container.read(imPresenceProjectionProvider.notifier);
      projection.observe(_session, _presence(false));
      await tester.pump();
      InitialAvatar avatar() => tester.widget<InitialAvatar>(
        find.byKey(const ValueKey('message-direct-avatar-direct')),
      );
      expect(avatar().online, false);
      await tester.pump(const Duration(seconds: 61));
      expect(avatar().online, isNull);
      expect(
        tester
            .widget<Semantics>(
              find.byKey(
                const ValueKey('message-conversation-semantics-direct'),
              ),
            )
            .properties
            .label,
        '单聊，状态未知',
      );
      projection.observe(_session, _presence(true, seconds: 2));
      await tester.pump();
      expect(avatar().online, true);
      expect(requests, 0);
      // This externally owned ProviderContainer outlives the widget tree;
      // finish its second expiry before Flutter's pending-timer invariant.
      await tester.pump(const Duration(seconds: 61));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  test(
    'presence projection rejects older samples and another session',
    () async {
      final container = ProviderContainer(
        overrides: [authControllerProvider.overrideWith(_FixtureAuth.new)],
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);
      final projection = container.read(imPresenceProjectionProvider.notifier);
      projection.observe(_session, _presence(false, seconds: 2));
      projection.observe(_session, _presence(true, seconds: 1));
      projection.observe(
        _session.withTokens(accessToken: 'fixture-obsolete'),
        _presence(true, seconds: 3),
      );
      expect(
        container
            .read(imPresenceProjectionProvider)['direct']
            ?.value
            .peerOnline,
        false,
      );
      (container.read(authControllerProvider.notifier) as _FixtureAuth).replace(
        _session.withTokens(accessToken: 'fixture-new-login'),
      );
      expect(container.read(imPresenceProjectionProvider), isEmpty);
      projection.observe(_session, _presence(true, seconds: 4));
      expect(container.read(imPresenceProjectionProvider), isEmpty);
    },
  );

  test('presence cache remains bounded without fetching directory or conversations', () async {
    final container = ProviderContainer(
      overrides: [authControllerProvider.overrideWith(_FixtureAuth.new)],
    );
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    final projection = container.read(imPresenceProjectionProvider.notifier);
    for (var index = 0; index < 160; index++) {
      projection.observe(_session, _presence(true, id: 'direct-$index'));
    }
    expect(container.read(imPresenceProjectionProvider), hasLength(128));
    expect(
      container.read(imPresenceProjectionProvider).containsKey('direct-0'),
      false,
    );
    expect(
      container.read(imPresenceProjectionProvider).containsKey('direct-159'),
      true,
    );
  });

  test(
    'direct resolution preserves group boundary and offline unknown state',
    () {
      final seen = DateTime.utc(2026, 9, 2);
      final direct = ImPresenceObservation(
        ImConversationPresence(
          conversationId: 'direct',
          type: 'direct',
          onlineMemberCount: 0,
          peerOnline: false,
          peerLastSeenAt: seen,
        ),
      );
      expect(
        resolveDirectPeerPresence(
          transportAvailable: true,
          member: oldPeer,
          observation: direct,
        ).online,
        false,
      );
      final disconnected = resolveDirectPeerPresence(
        transportAvailable: false,
        member: oldPeer,
        observation: direct,
      );
      expect(disconnected.online, isNull);
      expect(disconnected.lastSeenAt, seen);
      const group = ImPresenceObservation(
        ImConversationPresence(
          conversationId: 'group',
          type: 'group',
          onlineMemberCount: 0,
          peerOnline: false,
        ),
      );
      expect(
        resolveDirectPeerPresence(
          transportAvailable: true,
          member: oldPeer,
          observation: group,
        ).online,
        isNull,
      );
      expect(
        resolveDirectPeerPresence(
          transportAvailable: true,
          member: oldPeer,
          directoryMember: self,
        ).online,
        isNull,
      );
      expect(
        resolveDirectPeerPresence(transportAvailable: true).online,
        isNull,
      );
    },
  );

  for (final mode in [
    'same-login',
    'other-login',
    'logout',
    'wrong-conversation',
    'wrong-type',
    'accepted',
  ]) {
    test(
      'repository presence result session and identity validation: $mode',
      () async {
        HttpOverrides.global = _RealHttp();
        addTearDown(() => HttpOverrides.global = null);
        FlutterSecureStorage.setMockInitialValues({});
        final sessions = SecureSessionStore();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final session = MobileSession(
          accessToken: 'fixture-old',
          deviceId: 'fixture-device',
          userId: 'self',
          displayName: 'Fixture',
          username: 'fixture',
          policySignatureKey: '',
          oaApiUrl: '',
          imApiUrl: 'http://127.0.0.1:${server.port}',
        );
        await sessions.saveSession(session);
        final entered = Completer<void>();
        final release = Completer<void>();
        var calls = 0;
        server.listen((request) async {
          calls++;
          entered.complete();
          await release.future;
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'conversationId': mode == 'wrong-conversation'
                  ? 'other'
                  : 'direct',
              'type': mode == 'wrong-type' ? 'channel' : 'direct',
              'onlineMemberCount': 0,
              'peerOnline': false,
              'serverTime': '2026-09-02T16:00:00Z',
            }),
          );
          await request.response.close();
        });
        final local = ImLocalStore(
          factory: databaseFactoryFfi,
          pathResolver: () async => inMemoryDatabasePath,
        );
        addTearDown(local.close);
        final repository = ImRepository(
          CollaborationClient(sessions),
          sessions,
          local,
        );
        final pending = repository.conversationPresence('direct');
        final assertion = mode == 'accepted'
            ? null
            : expectLater(
                pending,
                throwsA(
                  mode.startsWith('wrong')
                      ? isA<FormatException>()
                      : isA<SessionChangedException>(),
                ),
              );
        await entered.future;
        if (mode == 'same-login') {
          await sessions.saveSession(
            session.withTokens(accessToken: 'fixture-new'),
          );
        }
        if (mode == 'other-login') {
          await sessions.saveSession(
            const MobileSession(
              accessToken: 'fixture-new',
              deviceId: 'other',
              userId: 'other',
              displayName: 'Other',
              username: 'other',
              policySignatureKey: '',
              imApiUrl: '',
              oaApiUrl: '',
            ),
          );
        }
        if (mode == 'logout') await sessions.clearSessionIfCurrent(session);
        release.complete();
        if (assertion != null) {
          await assertion;
        } else {
          expect((await pending).peerOnline, false);
        }
        expect(calls, 1);
      },
    );
  }
}

const _session = MobileSession(
  accessToken: 'fixture-session',
  deviceId: 'fixture-device',
  userId: 'self',
  displayName: 'Fixture',
  username: 'fixture',
  policySignatureKey: '',
  imApiUrl: '',
  oaApiUrl: '',
);

class _FixtureAuth extends AuthController {
  @override
  Future<MobileSession?> build() async => _session;
  void replace(MobileSession? value) => state = AsyncData(value);
}

ImConversationPresence _presence(
  bool online, {
  int seconds = 0,
  String id = 'direct',
}) => ImConversationPresence(
  conversationId: id,
  type: 'direct',
  onlineMemberCount: online ? 1 : 0,
  peerOnline: online,
  serverTime: DateTime.utc(2026, 9, 2, 16, 0, seconds),
);

class _RealHttp extends HttpOverrides {}
