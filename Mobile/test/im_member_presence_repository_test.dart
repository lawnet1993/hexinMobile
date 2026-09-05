import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/auth/application/auth_controller.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_member_presence.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _RealHttp extends HttpOverrides {}

class _Auth extends AuthController {
  _Auth(this.initial);
  final MobileSession initial;
  @override
  Future<MobileSession?> build() async => initial;
  void replace(MobileSession? value) => state = AsyncData(value);
}

const _self = ImMember(
  id: 'employee-self',
  username: 'self',
  displayName: 'Self',
  isOnline: true,
);
const _peer = ImMember(
  id: 'peer',
  username: 'peer',
  displayName: 'Peer',
  isOnline: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late HttpServer server;
  late SecureSessionStore sessions;
  late ImLocalStore local;
  late ProviderContainer container;
  late ImRepository repository;
  late MobileSession session;
  late ImMemberPresenceProjection projection;
  late Future<void> Function(HttpRequest) respond;
  late List<String> paths;
  setUp(() async {
    HttpOverrides.global = _RealHttp();
    FlutterSecureStorage.setMockInitialValues({});
    sessions = SecureSessionStore();
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    session = MobileSession(
      accessToken: 'fixture',
      deviceId: 'fixture',
      userId: 'account-self',
      username: 'self',
      displayName: 'Self',
      policySignatureKey: '',
      oaApiUrl: '',
      imApiUrl: 'http://127.0.0.1:${server.port}',
    );
    await sessions.saveSession(session);
    local = ImLocalStore(
      factory: databaseFactoryFfi,
      pathResolver: () async => inMemoryDatabasePath,
    );
    await local.replaceBootstrap(
      session.userId,
      const ImBootstrap(
        currentMember: _self,
        contacts: [_peer],
        conversations: [],
      ),
    );
    await local.replaceConversationMembers(session.userId, 'direct', [
      _self,
      _peer,
    ]);
    container = ProviderContainer(
      overrides: [authControllerProvider.overrideWith(() => _Auth(session))],
    );
    await container.read(authControllerProvider.future);
    projection = container.read(imMemberPresenceProjectionProvider.notifier);
    repository = ImRepository(
      CollaborationClient(sessions),
      sessions,
      local,
      memberPresence: () => projection,
    );
    paths = [];
    server.listen((request) async {
      paths.add(request.uri.path);
      await respond(request);
    });
  });
  tearDown(() async {
    await server.close(force: true);
    container.dispose();
    await local.close();
    HttpOverrides.global = null;
  });
  Future<void> json(HttpRequest request, Object body) async {
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(body));
    await request.response.close();
  }

  Map<String, Object?> peer(bool online) => {
    'id': 'peer',
    'userName': 'peer',
    'displayName': 'Peer',
    'isOnline': online,
    'lastSeenAt': '2026-09-03T00:00:00Z',
  };
  ImMemberPresenceObservation? value() =>
      container.read(imMemberPresenceProjectionProvider)['peer'];

  for (final paged in [false, true]) {
    test(
      'delayed bootstrap cannot override a newer ${paged ? 'paged' : 'full'} member response',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        respond = (request) async {
          if (request.uri.path.endsWith('/bootstrap')) {
            entered.complete();
            await release.future;
            await json(request, {
              'currentMember': {'id': 'employee-self'},
              'contacts': [peer(true)],
              'conversations': [],
            });
          } else {
            await json(
              request,
              paged
                  ? {
                      'items': [peer(false)],
                      'page': 1,
                      'pageSize': 50,
                      'total': 1,
                    }
                  : [peer(false)],
            );
          }
        };
        final old = repository.refreshBootstrap();
        await entered.future;
        if (paged) {
          await repository.conversationMemberPage('group');
        } else {
          await repository.refreshConversationMembers('group');
        }
        expect(value()?.online, false);
        release.complete();
        await old;
        expect(value()?.online, false);
        // The old source still exists in SQLite; presentation must use the
        // authoritative projection, not fixed source priority or cached booleans.
        expect(
          (await local.readBootstrap(session.userId))!.contacts.single.isOnline,
          true,
        );
        expect(paths, hasLength(2));
      },
    );
  }

  test(
    'known direct peer updates member state while a group count never does',
    () async {
      respond = (request) => json(request, {
        'conversationId': request.uri.path.contains('/direct/')
            ? 'direct'
            : 'group',
        'type': request.uri.path.contains('/direct/') ? 'direct' : 'group',
        'onlineMemberCount': 0,
        'peerOnline': false,
        'peerLastSeenAt': '2026-09-03T00:00:00Z',
      });
      await repository.conversationPresence('direct');
      expect(value()?.online, false);
      projection.observe(session, projection.beginRequest(), [_peer]);
      await repository.conversationPresence('group');
      expect(value()?.online, true);
      expect(
        paths,
        hasLength(2),
        reason:
            'direct identity lookup uses local cache, not another HTTP request',
      );
    },
  );

  test(
    'ambiguous direct membership cannot assign presence to an arbitrary person',
    () async {
      await local.mergeConversationMembers(session.userId, 'direct', [
        const ImMember(
          id: 'another',
          username: 'another',
          displayName: 'Another',
          isOnline: false,
        ),
      ]);
      respond = (request) => json(request, {
        'conversationId': 'direct',
        'type': 'direct',
        'onlineMemberCount': 0,
        'peerOnline': false,
      });
      await repository.conversationPresence('direct');
      expect(container.read(imMemberPresenceProjectionProvider), isEmpty);
    },
  );

  test(
    'member account search publishes a session-scoped presence sample',
    () async {
      respond = (request) => json(request, peer(false));
      expect((await repository.searchMembers('peer')).single.id, 'peer');
      expect(value()?.online, false);
      expect(paths, ['/api/im/members/search']);
    },
  );

  for (final type in ['managers', 'managers-page', 'muted']) {
    test(
      '$type shares a live sample and rejects stale-login replies',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        var delayed = false;
        respond = (request) async {
          if (delayed) {
            entered.complete();
            await release.future;
          }
          await json(
            request,
            type == 'managers'
                ? [peer(false)]
                : {
                    'items': [
                      type == 'muted' ? {'member': peer(false)} : peer(false),
                    ],
                    'page': 1,
                    'pageSize': 50,
                    'total': 1,
                  },
          );
        };
        Future<Object?> load() => switch (type) {
          'managers' => repository.groupManagers('group'),
          'managers-page' => repository.groupManagersPage('group'),
          _ => repository.groupMutedMembers('group'),
        };
        await load();
        expect(value()?.online, false);
        delayed = true;
        final pending = load();
        final assertion = expectLater(
          pending,
          throwsA(isA<SessionChangedException>()),
        );
        await entered.future;
        final replacement = session.withTokens(accessToken: 'fixture-new');
        await sessions.saveSession(replacement);
        (container.read(authControllerProvider.notifier) as _Auth).replace(
          replacement,
        );
        expect(container.read(imMemberPresenceProjectionProvider), isEmpty);
        release.complete();
        await assertion;
        expect(container.read(imMemberPresenceProjectionProvider), isEmpty);
      },
    );
  }

  for (final type in ['bootstrap', 'members/page', 'presence', 'search']) {
    test(
      'late $type result cannot repopulate the next login presence',
      () async {
        final entered = Completer<void>();
        final release = Completer<void>();
        respond = (request) async {
          entered.complete();
          await release.future;
          await json(request, switch (type) {
            'bootstrap' => {
              'currentMember': {'id': 'employee-self'},
              'contacts': [peer(true)],
              'conversations': [],
            },
            'members/page' => {
              'items': [peer(true)],
              'page': 1,
              'pageSize': 50,
              'total': 1,
            },
            'presence' => {
              'conversationId': 'direct',
              'type': 'direct',
              'peerOnline': true,
              'onlineMemberCount': 1,
            },
            _ => peer(true),
          });
        };
        final Future<Object?> pending = switch (type) {
          'bootstrap' => repository.refreshBootstrap(),
          'members/page' => repository.conversationMemberPage('group'),
          'presence' => repository.conversationPresence('direct'),
          _ => repository.searchMembers('peer'),
        };
        final assertion = expectLater(
          pending,
          throwsA(isA<SessionChangedException>()),
        );
        await entered.future;
        final replacement = session.withTokens(accessToken: 'fixture-relogin');
        await sessions.saveSession(replacement);
        (container.read(authControllerProvider.notifier) as _Auth).replace(
          replacement,
        );
        expect(container.read(imMemberPresenceProjectionProvider), isEmpty);
        release.complete();
        await assertion;
        expect(container.read(imMemberPresenceProjectionProvider), isEmpty);
      },
    );
  }

  test('cancelled presence HTTP cannot publish a late member observation', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    final finished = Completer<void>();
    respond = (request) async {
      entered.complete();
      await release.future;
      await json(request, {'conversationId': 'direct', 'type': 'direct',
        'peerOnline': true, 'onlineMemberCount': 1});
      finished.complete();
    };
    final cancellation = CancelToken();
    final pending = repository.conversationPresence('direct', cancelToken: cancellation);
    final assertion = expectLater(pending, throwsA(isA<DioException>().having(
      (error) => error.type, 'type', DioExceptionType.cancel)));
    await entered.future;
    cancellation.cancel();
    await assertion;
    release.complete();
    await finished.future;
    expect(container.read(imMemberPresenceProjectionProvider), isEmpty);
  });
}
