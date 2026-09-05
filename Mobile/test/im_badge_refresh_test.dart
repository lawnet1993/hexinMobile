import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'durable visible read refreshes badges without a read echo event',
    () async {
      final fixture = await _Fixture.create();
      expect(
        (await fixture.container.read(imBadgeSummaryProvider.future))
            .unreadMessages,
        2,
      );
      await fixture.readVisible();
      final badges = await fixture.container.read(
        imBadgeSummaryProvider.future,
      );
      expect(badges.unreadMessages, 0);
      expect(badges.pendingFriendRequests, 3);
      expect(fixture.badgeRequests, 2);
      expect(
        (await fixture.store.readBootstrap('account'))!
            .conversations
            .single
            .unreadCount,
        0,
      );
    },
  );

  test('unchanged unread sum does not refetch on metadata or reload', () async {
    final fixture = await _Fixture.create();
    await fixture.container.read(imBadgeSummaryProvider.future);
    await fixture.store.replaceBootstrap(
      'account',
      _bootstrap(title: 'Renamed'),
    );
    for (var i = 0; i < 3; i++) {
      fixture.container.invalidate(imBootstrapProvider);
      await fixture.container.read(imBootstrapProvider.future);
      await fixture.container.pump();
    }
    expect(
      (await fixture.container.read(imBadgeSummaryProvider.future))
          .unreadMessages,
      2,
    );
    expect(fixture.badgeRequests, 1);
  });

  test(
    'late pre-read badge response cannot restore the old unread total',
    () async {
      final fixture = await _Fixture.create(holdFirstBadge: true);
      await fixture.firstBadgeArrived.future.timeout(
        const Duration(seconds: 5),
      );
      await fixture.readVisible();
      final newResult = fixture.container.read(imBadgeSummaryProvider.future);
      // Release the older snapshot only after the local invalidation has run.
      fixture.releaseFirstBadge.complete();
      expect((await newResult).unreadMessages, 0);
      await fixture.container.pump();
      expect(
        fixture.container.read(imBadgeSummaryProvider).value!.unreadMessages,
        0,
      );
      expect(fixture.badgeRequests, 2);
    },
  );
}

class _Fixture {
  _Fixture(
    this.server,
    this.sessions,
    this.store,
    this.repository,
    this.container,
  );

  final HttpServer server;
  final SecureSessionStore sessions;
  final ImLocalStore store;
  final ImRepository repository;
  final ProviderContainer container;
  final firstBadgeArrived = Completer<void>();
  final releaseFirstBadge = Completer<void>();
  var unread = 2;
  var badgeRequests = 0;

  static Future<_Fixture> create({bool holdFirstBadge = false}) async {
    HttpOverrides.global = _RealHttpOverrides();
    addTearDown(() => HttpOverrides.global = null);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    FlutterSecureStorage.setMockInitialValues({});
    final sessions = SecureSessionStore();
    await sessions.saveSession(
      MobileSession(
        accessToken: 'local-fixture-token',
        deviceId: 'local-device',
        userId: 'account',
        displayName: 'Test',
        username: 'test',
        policySignatureKey: '',
        imApiUrl: 'http://127.0.0.1:${server.port}',
        oaApiUrl: '',
      ),
    );
    final store = ImLocalStore(
      factory: databaseFactoryFfi,
      pathResolver: () async => inMemoryDatabasePath,
    );
    addTearDown(store.close);
    await store.replaceBootstrap('account', _bootstrap());
    final repository = ImRepository(
      CollaborationClient(sessions),
      sessions,
      store,
    );
    final container = ProviderContainer(
      overrides: [
        collaborationAccountScopeProvider.overrideWithValue('account'),
        imRepositoryProvider.overrideWithValue(repository),
        imBootstrapProvider.overrideWith(
          (ref) async => (await store.readBootstrap('account'))!,
        ),
      ],
    );
    addTearDown(container.dispose);
    final fixture = _Fixture(server, sessions, store, repository, container);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      switch (request.uri.path) {
        case '/api/im/badges':
          final snapshot = fixture.unread;
          fixture.badgeRequests++;
          if (!fixture.firstBadgeArrived.isCompleted) {
            fixture.firstBadgeArrived.complete();
          }
          if (holdFirstBadge && fixture.badgeRequests == 1) {
            await fixture.releaseFirstBadge.future;
          }
          request.response.write(
            jsonEncode({
              'unreadMessages': snapshot,
              'pendingFriendRequests': 3,
            }),
          );
        case '/api/im/conversations/group/read':
          final payload =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          expect(request.method, 'POST');
          expect(payload['sequence'], 2);
          fixture.unread = 0;
          request.response.statusCode = 204;
        case '/api/im/mentions/unread':
          request.response.write('[]');
        default:
          request.response.statusCode = 404;
      }
      await request.response.close();
    });
    await container.read(imBootstrapProvider.future);
    container.listen(imBadgeSummaryProvider, (_, _) {});
    return fixture;
  }

  Future<void> readVisible() async {
    await repository.markRead('group', 2);
    // This is exactly the page's invalidation, with no coordinator/read event.
    container.invalidate(imBootstrapProvider);
    await container.read(imBootstrapProvider.future);
    await container.pump();
  }
}

ImBootstrap _bootstrap({String title = 'Group'}) => ImBootstrap(
  currentMember: const ImMember(
    id: 'account',
    username: 'test',
    displayName: 'Test',
    isOnline: true,
  ),
  contacts: const [],
  conversations: [
    ImConversation.fromJson({
      'id': 'group',
      'type': 'group',
      'title': title,
      'lastMessageSequence': 2,
      'lastReadSequence': 0,
      'unreadCount': 2,
    }),
  ],
);

class _RealHttpOverrides extends HttpOverrides {}
