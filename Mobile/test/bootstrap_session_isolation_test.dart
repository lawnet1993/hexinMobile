import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/im_cache_cipher.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/oa_local_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  for (final logout in [false, true]) {
    test(
      'cache commit is serialized with ${logout ? 'logout' : 'login'}',
      () async {
        FlutterSecureStorage.setMockInitialValues({});
        final sessions = SecureSessionStore();
        const old = MobileSession(
          accessToken: 'fixture-old',
          deviceId: 'fixture-device',
          userId: 'a',
          displayName: 'Fixture',
          username: 'fixture',
          policySignatureKey: '',
          imApiUrl: '',
          oaApiUrl: '',
        );
        await sessions.saveSession(old);
        final entered = Completer<void>();
        final release = Completer<void>();
        final order = <String>[];
        final commit = sessions.withCurrentSession(old, () async {
          entered.complete();
          await release.future;
          order.add('commit');
        });
        await entered.future;
        final transition =
            (logout
                    ? sessions.clearSession()
                    : sessions.saveSession(
                        old.withTokens(accessToken: 'fixture-new'),
                      ))
                .then((_) => order.add('session-changed'));
        expect(order, isEmpty);
        release.complete();
        await Future.wait([commit, transition]);
        expect(order, ['commit', 'session-changed']);
        await expectLater(
          sessions.withCurrentSession(
            old,
            () async => order.add('stale-write'),
          ),
          throwsA(isA<SessionChangedException>()),
        );
        expect(order, ['commit', 'session-changed']);
        // A rejected obsolete write must not poison the session lock.
        await sessions.saveSession(
          old.withTokens(accessToken: 'fixture-latest'),
        );
        expect((await sessions.readSession())?.accessToken, 'fixture-latest');
      },
    );
  }

  for (final service in ['im', 'oa']) {
    group('$service bootstrap session ownership', () {
      late SecureSessionStore sessions;
      late HttpServer server;
      late int port;
      late Directory directory;
      late ImLocalStore imStore;
      late OaLocalStore oaStore;
      late ImRepository im;
      late OaRepository oa;
      late Future<void> Function(HttpRequest request) respond;
      late List<String?> requestAccounts;

      MobileSession session(String token, String account) => MobileSession(
        accessToken: token,
        deviceId: 'fixture-device',
        userId: account,
        displayName: account,
        username: account,
        policySignatureKey: '',
        imApiUrl: 'http://127.0.0.1:$port',
        oaApiUrl: 'http://127.0.0.1:$port',
      );

      Future<void> reply(
        HttpRequest request,
        String account,
        String name,
      ) async {
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'currentMember': {
              'id': account,
              'username': account,
              'displayName': name,
            },
            'contacts': [],
            'conversations': [],
            'notifications': [],
            'todos': [],
            'approvalTemplates': [],
          }),
        );
        await request.response.close();
      }

      Future<Object> refresh() =>
          service == 'im' ? im.refreshBootstrap() : oa.refreshBootstrap();
      Future<Object> cacheFirst() =>
          service == 'im' ? im.bootstrapCacheFirst() : oa.bootstrapCacheFirst();
      Future<String?> cachedName(String account) async => service == 'im'
          ? (await imStore.readBootstrap(account))?.currentMember.displayName
          : ((await oaStore.readObject(
                      account,
                      OaLocalStore.bootstrapCacheKey,
                    ))?['currentMember']
                    as Map?)?['displayName']
                as String?;

      setUp(() async {
        HttpOverrides.global = _RealHttp();
        FlutterSecureStorage.setMockInitialValues({});
        sessions = SecureSessionStore();
        directory = await Directory.systemTemp.createTemp('bootstrap-session-');
        imStore = ImLocalStore(
          factory: databaseFactoryFfi,
          pathResolver: () async => '${directory.path}/im.db',
        );
        oaStore = OaLocalStore.withOptions(
          databaseFactoryFfi,
          () async => '${directory.path}/oa.db',
          const PlainImCacheCipher(),
        );
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        port = server.port;
        requestAccounts = [];
        respond = (request) => reply(request, 'a', 'original');
        server.listen((request) async {
          requestAccounts.add(request.headers.value('X-Terminal-Account-Id'));
          expect(request.uri.path, '/api/$service/bootstrap');
          await respond(request);
        });
        final client = CollaborationClient(sessions);
        im = ImRepository(client, sessions, imStore);
        oa = OaRepository(client, sessions, oaStore);
        await sessions.saveSession(session('fixture-original', 'a'));
      });
      tearDown(() async {
        await server.close(force: true);
        await imStore.close();
        await oaStore.close();
        await directory.delete(recursive: true);
        HttpOverrides.global = null;
      });

      for (final transition in [
        'account switch',
        'same account relogin',
        'logout',
      ]) {
        test(
          'rejects late response after $transition without cache write',
          () async {
            respond = (request) async {
              if (transition == 'logout') {
                await sessions.clearSession();
              } else {
                await sessions.saveSession(
                  session(
                    'fixture-new',
                    transition == 'account switch' ? 'b' : 'a',
                  ),
                );
              }
              await reply(request, 'a', 'stale');
            };
            await expectLater(
              refresh(),
              throwsA(isA<SessionChangedException>()),
            );
            expect(requestAccounts, ['a']);
            expect(await cachedName('a'), isNull);
            expect(await cachedName('b'), isNull);
          },
        );
      }

      test(
        'late old refresh cannot overwrite completed new same-account refresh',
        () async {
          final entered = Completer<void>();
          final release = Completer<void>();
          addTearDown(() {
            if (!release.isCompleted) release.complete();
          });
          respond = (request) async {
            if (request.headers.value('Authorization') ==
                'Bearer fixture-original') {
              entered.complete();
              await release.future;
              await reply(request, 'a', 'stale');
            } else {
              await reply(request, 'a', 'new session');
            }
          };
          final pending = refresh();
          final rejected = expectLater(
            pending,
            throwsA(isA<SessionChangedException>()),
          );
          await entered.future;
          await sessions.saveSession(session('fixture-new', 'a'));
          await refresh();
          expect(await cachedName('a'), 'new session');
          release.complete();
          await rejected;
          expect(await cachedName('a'), 'new session');
          expect(requestAccounts, ['a', 'a']);
        },
      );

      test('current refresh persists and offline cache-first does not request again', () async {
        await refresh();
        expect(await cachedName('a'), 'original');
        await server.close(force: true);
        await cacheFirst();
        expect(requestAccounts, ['a']);
        await sessions.saveSession(session('fixture-b', 'b'));
        await expectLater(cacheFirst(), throwsA(anything));
        expect(await cachedName('b'), isNull);
        expect(await cachedName('a'), 'original');
      });
    });
  }
}

class _RealHttp extends HttpOverrides {}
