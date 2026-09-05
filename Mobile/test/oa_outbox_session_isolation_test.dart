import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/im_cache_cipher.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/oa_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  for (final failure in ['expired', 'replaced', 'business-conflict']) {
    test(
      '$failure preserves authentication failures but not business conflicts',
      () async {
        HttpOverrides.global = _RealHttp();
        addTearDown(() => HttpOverrides.global = null);
        FlutterSecureStorage.setMockInitialValues({});
        final sessions = SecureSessionStore();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final directory = await Directory.systemTemp.createTemp(
          'oa-auth-retry-',
        );
        final store = OaLocalStore.withOptions(
          databaseFactoryFfi,
          () async => '${directory.path}/oa.db',
          const PlainImCacheCipher(),
        );
        addTearDown(() async {
          await store.close();
          await directory.delete(recursive: true);
        });
        final old = MobileSession(
          accessToken: 'fixture-old',
          userId: 'a',
          deviceId: 'fixture-device',
          username: 'a',
          displayName: 'a',
          policySignatureKey: '',
          imApiUrl: '',
          oaApiUrl: 'http://127.0.0.1:${server.port}',
        );
        await sessions.saveSession(old);
        final ids = <String>[];
        var reject = true;
        server.listen((request) async {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join()) as Map;
          ids.add(body['clientRequestId'] as String);
          request.response.headers.contentType = ContentType.json;
          if (reject) {
            request.response.statusCode = failure == 'expired' ? 401 : 409;
            request.response.write(
              jsonEncode({
                'code': failure == 'replaced'
                    ? 'session_replaced'
                    : 'business_conflict',
              }),
            );
          } else {
            request.response.write('{"id":"approval-a"}');
          }
          await request.response.close();
        });
        for (final id in ['one', 'two']) {
          await store.enqueue(
            'a',
            id: id,
            idempotencyKey: id,
            commandType: 'submit-approval',
            payload: {'clientRequestId': id, 'formDataJson': '{}'},
          );
        }
        final repository = OaRepository(
          CollaborationClient(sessions),
          sessions,
          store,
        );
        expect(await repository.flushOutbox(), 0);
        final items = await store.readOutbox('a');
        if (failure == 'business-conflict') {
          expect(ids, hasLength(2));
          expect(items.every((item) => item.state == 'failed'), true);
        } else {
          expect(ids, hasLength(1));
          expect(items.every((item) => item.state == 'pending'), true);
          expect(items.map((item) => item.attempts).reduce((a, b) => a + b), 1);
          reject = false;
          await sessions.saveSession(
            old.withTokens(accessToken: 'fixture-new'),
          );
          for (final item in items) {
            await store.retryOutbox('a', item.id);
          }
          expect(await repository.flushOutbox(), 2);
          expect(ids.skip(1).toSet(), {'one', 'two'});
          expect(await store.readOutbox('a'), isEmpty);
        }
      },
    );
  }
  for (final entry in ['submit', 'flush']) {
    for (final transition in ['account', 'relogin', 'logout']) {
      test(
        '$entry stops after attachment response on $transition and remains retryable',
        () async {
          HttpOverrides.global = _RealHttp();
          addTearDown(() => HttpOverrides.global = null);
          FlutterSecureStorage.setMockInitialValues({});
          final sessions = SecureSessionStore();
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          addTearDown(() => server.close(force: true));
          final directory = await Directory.systemTemp.createTemp(
            'oa-session-',
          );
          final store = OaLocalStore.withOptions(
            databaseFactoryFfi,
            () async => '${directory.path}/oa.db',
            const PlainImCacheCipher(),
          );
          addTearDown(() async {
            await store.close();
            await directory.delete(recursive: true);
          });
          MobileSession session(String token, String account) => MobileSession(
            accessToken: token,
            userId: account,
            deviceId: 'fixture-device',
            username: account,
            displayName: account,
            policySignatureKey: '',
            imApiUrl: '',
            oaApiUrl: 'http://127.0.0.1:${server.port}',
          );
          await sessions.saveSession(session('fixture-old', 'a'));
          final repository = OaRepository(
            CollaborationClient(sessions),
            sessions,
            store,
          );
          var interrupt = true;
          final approvalAccounts = <String?>[];
          final approvalClientIds = <String?>[];
          final uploadAccounts = <String?>[];
          server.listen((request) async {
            request.response.headers.contentType = ContentType.json;
            if (request.uri.path == '/api/oa/attachments') {
              await request.drain<void>();
              uploadAccounts.add(
                request.headers.value('X-Terminal-Account-Id'),
              );
              if (interrupt) {
                interrupt = false;
                if (transition == 'logout') {
                  await sessions.clearSession();
                } else {
                  await sessions.saveSession(
                    session('fixture-new', transition == 'account' ? 'b' : 'a'),
                  );
                }
              }
              request.response.write(
                jsonEncode({
                  'id': 'attachment-${uploadAccounts.length}',
                  'fileName': 'fixture.txt',
                }),
              );
            } else if (request.uri.path == '/api/oa/approval-requests') {
              final body =
                  jsonDecode(await utf8.decoder.bind(request).join()) as Map;
              approvalAccounts.add(
                request.headers.value('X-Terminal-Account-Id'),
              );
              approvalClientIds.add(body['clientRequestId'] as String?);
              request.response.write('{"id":"approval-a"}');
            } else {
              request.response.statusCode = 404;
            }
            await request.response.close();
          });
          final attachment = OaLocalAttachment(
            id: 'local-file',
            fileName: 'fixture.txt',
            contentType: 'text/plain',
            bytes: utf8.encode('fixture-body'),
            formFieldId: 'proof',
          );
          if (entry == 'submit') {
            await expectLater(
              repository.submitApproval(
                applicationKey: 'expense',
                template: const OaApprovalTemplate(
                  id: 'template-a',
                  name: 'Fixture',
                  category: 'Fixture',
                  workflowKey: 'flow-a',
                ),
                title: 'AI-UAT-session',
                formData: const {'amount': 1},
                pendingAttachments: [attachment],
                allowOfflineQueue: true,
              ),
              throwsA(isA<SessionChangedException>()),
            );
          } else {
            await store.enqueue(
              'a',
              id: 'outbox-a',
              idempotencyKey: 'client-a',
              commandType: 'submit-approval',
              payload: {
                'clientRequestId': 'client-a',
                'title': 'AI-UAT-session',
                'formDataJson': '{"amount":1}',
                'pendingAttachments': [attachment.toJson()],
              },
            );
            expect(await repository.flushOutbox(), 0);
          }
          expect(approvalAccounts, isEmpty);
          expect(uploadAccounts, ['a']);
          final pending = (await store.readOutbox('a')).single;
          expect(pending.state, 'pending');
          expect(pending.attempts, 0);
          expect(pending.lastError, isEmpty);
          expect(await store.readOutbox('b'), isEmpty);
          final stableId = pending.payload['clientRequestId'];
          // Resume the original account with a fresh session, not the old token.
          await sessions.saveSession(session('fixture-resumed', 'a'));
          expect(await repository.flushOutbox(), 1);
          expect(approvalAccounts, ['a']);
          expect(approvalClientIds, [stableId]);
          expect(await store.readOutbox('a'), isEmpty);
          expect(await store.readOutbox('b'), isEmpty);
        },
      );
    }
  }

  for (final status in [200, 500]) {
    test(
      'late approval $status does not consume or fail old queue after account switch',
      () async {
        HttpOverrides.global = _RealHttp();
        addTearDown(() => HttpOverrides.global = null);
        FlutterSecureStorage.setMockInitialValues({});
        final sessions = SecureSessionStore();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() => server.close(force: true));
        final directory = await Directory.systemTemp.createTemp(
          'oa-late-submit-',
        );
        final store = OaLocalStore.withOptions(
          databaseFactoryFfi,
          () async => '${directory.path}/oa.db',
          const PlainImCacheCipher(),
        );
        addTearDown(() async {
          await store.close();
          await directory.delete(recursive: true);
        });
        MobileSession session(String account) => MobileSession(
          accessToken: 'fixture-$account',
          userId: account,
          deviceId: 'fixture-device',
          username: account,
          displayName: account,
          policySignatureKey: '',
          imApiUrl: '',
          oaApiUrl: 'http://127.0.0.1:${server.port}',
        );
        await sessions.saveSession(session('a'));
        final accounts = <String?>[];
        server.listen((request) async {
          await request.drain<void>();
          accounts.add(request.headers.value('X-Terminal-Account-Id'));
          await sessions.saveSession(session('b'));
          request.response.statusCode = status;
          request.response.headers.contentType = ContentType.json;
          request.response.write('{"id":"approval-a"}');
          await request.response.close();
        });
        for (final id in ['one', 'two']) {
          await store.enqueue(
            'a',
            id: id,
            idempotencyKey: id,
            commandType: 'submit-approval',
            payload: {
              'clientRequestId': id,
              'title': 'AI-UAT-$id',
              'formDataJson': '{}',
            },
          );
        }
        final repository = OaRepository(
          CollaborationClient(sessions),
          sessions,
          store,
        );
        expect(await repository.flushOutbox(), 0);
        expect(accounts, ['a']);
        final pending = await store.readOutbox('a');
        expect(pending, hasLength(2));
        expect(
          pending.every(
            (item) => item.state == 'pending' && item.attempts == 0,
          ),
          true,
        );
        expect(await store.readOutbox('b'), isEmpty);
      },
    );
  }
}

class _RealHttp extends HttpOverrides {}
