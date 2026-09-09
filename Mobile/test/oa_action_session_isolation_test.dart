import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

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
  late _Fixture f;
  setUp(() async {
    HttpOverrides.global = _RealHttp();
    f = await _Fixture.create();
  });
  tearDown(() async {
    await f.close();
    HttpOverrides.global = null;
  });

  for (final action in [
    'attachment',
    'attachment-thumbnail',
    'attachment-preview',
    'review',
    'withdraw',
    'transfer',
    'add-sign',
    'return',
    'remind',
  ]) {
    for (final change in ['account', 'relogin', 'logout']) {
      test('dialog-bound $action never sends under a later $change', () async {
        final original = (await f.sessions.readSession())!;
        final before = await f.snapshot();
        await f.transition(change);
        await expectLater(
          f.performBound(action, original),
          throwsA(isA<SessionChangedException>()),
        );
        expect(f.paths, isEmpty);
        expect(await f.snapshot(), before);
      });
    }
  }

  for (final kind in [
    'attachment',
    'attachment-thumbnail',
    'attachment-preview',
  ]) {
    test('$kind returns bytes for the unchanged session', () async {
      expect(await f.perform(kind), isNotEmpty);
      expect(f.identities, [true]);
    });
    test(
      '$kind canceled before dispatch does not request the server',
      () async {
        final cancel = CancelToken()..cancel('fixture-navigation');
        await expectLater(
          switch (kind) {
            'attachment' => f.repository.downloadAttachment(
              'proof',
              cancelToken: cancel,
            ),
            'attachment-thumbnail' => f.repository.downloadAttachmentThumbnail(
              'proof',
              cancelToken: cancel,
            ),
            _ => f.repository.downloadAttachmentPreview(
              'proof',
              cancelToken: cancel,
            ),
          },
          throwsA(
            isA<DioException>().having(
              (error) => error.type,
              'type',
              DioExceptionType.cancel,
            ),
          ),
        );
        expect(f.paths, isEmpty);
      },
    );
  }

  test('attachment file download streams bytes and reports progress', () async {
    final directory = await Directory.systemTemp.createTemp('oa-download-');
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final target = File('${directory.path}${Platform.pathSeparator}proof.bin');
    final progress = <(int, int)>[];

    await f.repository.downloadAttachmentToFile(
      'proof',
      target.path,
      onReceiveProgress: (received, total) => progress.add((received, total)),
    );

    expect(await target.exists(), isTrue);
    expect(await target.length(), greaterThan(0));
    expect(progress, isNotEmpty);
    expect(progress.last.$1, await target.length());
    expect(
      progress.last.$2 == -1 || progress.last.$2 == progress.last.$1,
      isTrue,
    );
    expect(File('${target.path}.part').existsSync(), isFalse);
    expect(f.identities, [true]);
  });

  for (final operation in [
    'attachment',
    'attachment-thumbnail',
    'attachment-preview',
    'detail',
    'network-detail',
    'page',
    'review',
    'withdraw',
    'cc-read',
    'preview',
    'read-all',
  ]) {
    for (final change in ['account', 'relogin', 'logout']) {
      test('OA $operation rejects late success after $change', () async {
        final before = await f.snapshot();
        f.beforeReply = (_) => f.transition(change);
        await expectLater(
          f.perform(operation),
          throwsA(isA<SessionChangedException>()),
        );
        expect(await f.snapshot(), before);
        expect(f.identities, [true]);
      });
    }
  }

  for (final operation in [
    'attachment',
    'attachment-thumbnail',
    'attachment-preview',
    'detail',
    'network-detail',
    'page',
    'review',
    'withdraw',
    'cc-read',
    'preview',
    'read-all',
  ]) {
    test('OA $operation classifies a late 500 as stale login', () async {
      final before = await f.snapshot();
      f.status = 500;
      f.beforeReply = (_) => f.transition('relogin');
      await expectLater(
        f.perform(operation),
        throwsA(isA<SessionChangedException>()),
      );
      expect(await f.snapshot(), before);
    });
  }

  for (final status in [200, 500]) {
    for (final change in ['account', 'relogin', 'logout']) {
      test(
        'OA receipt $status after $change preserves both pending intents',
        () async {
          await f.repository.markNotificationRead('n1');
          await f.repository.markNotificationRead('n2');
          f.status = status;
          f.beforeReply = (_) => f.transition(change);
          expect(await f.repository.flushNotificationReads(), 0);
          expect(await f.store.pendingNotificationReadCount('a'), 2);
          final due = await f.store.dueNotificationReads('a');
          expect(due.length, 2);
          expect(due.map((item) => item['attempts']), [0, 0]);
          expect(f.paths.length, 1);
          expect(f.identities, [true]);
        },
      );
    }
  }

  for (final status in [401, 409]) {
    test(
      'OA receipt session failure $status stays pending and stops the batch',
      () async {
        await f.repository.markNotificationRead('n1');
        await f.repository.markNotificationRead('n2');
        f.status = status;
        f.code = 'session_replaced';
        expect(await f.repository.flushNotificationReads(), 0);
        expect(f.paths.length, 1);
        // A session failure is retriable after login, not a permanent business failure.
        await f.transition('relogin');
        f.status = 200;
        expect(await f.repository.flushNotificationReads(retryNow: true), 2);
        expect(await f.store.pendingNotificationReadCount('a'), 0);
      },
    );
  }

  test(
    'OA receipt flush for the new account does not join the old account future',
    () async {
      await f.repository.markNotificationRead('n1');
      final started = Completer<void>();
      final release = Completer<void>();
      f.beforeReply = (request) async {
        if (request.headers.value('X-Terminal-Account-Id') == 'a') {
          started.complete();
          await release.future;
        }
      };
      final oldFlush = f.repository.flushNotificationReads();
      await started.future;
      await f.transition('account');
      await f.repository.markNotificationRead('n2');
      final newFlush = f.repository.flushNotificationReads();
      try {
        expect(await newFlush.timeout(const Duration(seconds: 1)), 1);
        expect(await f.store.pendingNotificationReadCount('b'), 0);
      } finally {
        release.complete();
        await oldFlush;
      }
      expect(await f.store.pendingNotificationReadCount('a'), 1);
    },
  );

  test(
    'OA current-session review retains method, version and idempotency fields',
    () async {
      final request = await f.repository.reviewApproval(
        requestId: 'request',
        taskId: 'task',
        expectedTaskVersion: 7,
        decision: 'approved',
        comment: 'AI-UAT',
      );
      expect(request.title, 'server-a');
      expect(f.methods, ['PATCH']);
      final body = f.bodies.single;
      expect(body['taskId'], 'task');
      expect(body['expectedTaskVersion'], 7);
      expect(body['idempotencyKey'], isNotEmpty);
      expect(
        (await f.store.readObject('a', 'approval:request'))!['title'],
        'server-a',
      );
      expect(
        await f.store.readObject('a', OaLocalStore.bootstrapCacheKey),
        isNull,
      );
      expect(
        await f.store.readObject('b', OaLocalStore.bootstrapCacheKey),
        isNotNull,
      );
    },
  );
}

class _Fixture {
  _Fixture(this.server, this.sessions, this.store);
  final HttpServer server;
  final SecureSessionStore sessions;
  final OaLocalStore store;
  late OaRepository repository;
  int status = 200;
  String code = '';
  Future<void> Function(HttpRequest) beforeReply = (_) async {};
  final paths = <String>[];
  final methods = <String>[];
  final identities = <bool>[];
  final bodies = <Map<String, Object?>>[];

  Future<void> login(String account, String suffix) => sessions.saveSession(
    MobileSession(
      accessToken: 'fixture-$suffix',
      deviceId: 'fixture-device',
      userId: account,
      displayName: account,
      username: account,
      policySignatureKey: '',
      imApiUrl: '',
      oaApiUrl: 'http://127.0.0.1:${server.port}',
    ),
  );

  Future<void> transition(String kind) => kind == 'logout'
      ? sessions.clearSession()
      : login(kind == 'account' ? 'b' : 'a', 'new');

  Future<Object?> performBound(String action, MobileSession session) {
    final task = OaApprovalTask.fromJson({'id': 'task', 'version': 7});
    return switch (action) {
      'attachment' => repository.downloadAttachment(
        'proof',
        expectedSession: session,
      ),
      'attachment-thumbnail' => repository.downloadAttachmentThumbnail(
        'proof',
        expectedSession: session,
      ),
      'attachment-preview' => repository.downloadAttachmentPreview(
        'proof',
        expectedSession: session,
      ),
      'review' => repository.reviewApproval(
        requestId: 'request',
        taskId: 'task',
        expectedTaskVersion: 7,
        decision: 'approved',
        comment: 'AI-UAT',
        expectedSession: session,
      ),
      'withdraw' => repository.withdrawApproval(
        requestId: 'request',
        reason: 'AI-UAT',
        expectedSession: session,
      ),
      'transfer' => repository.transferApproval(
        requestId: 'request',
        task: task,
        newAssigneeId: 'peer',
        reason: 'AI-UAT',
        expectedSession: session,
      ),
      'add-sign' => repository.addSignApproval(
        requestId: 'request',
        task: task,
        addedAssigneeId: 'peer',
        mode: 'before',
        comment: 'AI-UAT',
        expectedSession: session,
      ),
      'return' => repository.returnApproval(
        requestId: 'request',
        task: task,
        reason: 'AI-UAT',
        expectedSession: session,
      ),
      'remind' => repository.remindApproval(
        requestId: 'request',
        comment: 'AI-UAT',
        expectedSession: session,
      ),
      _ => throw StateError('Unknown bound action'),
    };
  }

  Future<Object?> perform(String operation) => switch (operation) {
    'attachment' => repository.downloadAttachment('fixture-attachment'),
    'attachment-thumbnail' => repository.downloadAttachmentThumbnail(
      'fixture-attachment',
    ),
    'attachment-preview' => repository.downloadAttachmentPreview(
      'fixture-attachment',
    ),
    'detail' => repository.refreshApprovalRequest('request'),
    'network-detail' => repository.approvalRequestNetworkFirst('request'),
    'page' => repository.approvalRequestsPage(),
    'review' => repository.reviewApproval(
      requestId: 'request',
      taskId: 'task',
      expectedTaskVersion: 7,
      decision: 'approved',
      comment: 'AI-UAT',
    ),
    'withdraw' => repository.withdrawApproval(
      requestId: 'request',
      reason: 'AI-UAT',
    ),
    'cc-read' => repository.markApprovalCcRead('request'),
    'preview' => repository.previewWorkflow(
      applicationKey: 'attendance.leave',
      template: OaApprovalTemplate.fromJson({'id': 'template', 'name': 'Test'}),
      formData: {},
    ),
    'read-all' => repository.markAllNotificationsRead(),
    _ => throw StateError('Unknown test operation'),
  };

  Future<Map<String, Object?>> snapshot() async => {
    for (final account in ['a', 'b'])
      account: {
        for (final key in [
          'approval:request',
          OaLocalStore.bootstrapCacheKey,
          OaLocalStore.notificationPageCacheKey,
        ])
          key: await store.readObject(account, key),
        'notices': await store.readList(
          account,
          OaLocalStore.notificationsCacheKey,
        ),
      },
  };

  static Future<_Fixture> create() async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = OaLocalStore.withOptions(
      databaseFactoryFfi,
      () async => inMemoryDatabasePath,
      const PlainImCacheCipher(),
    );
    final f = _Fixture(
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
      SecureSessionStore(),
      store,
    );
    await f.login('a', 'old');
    for (final account in ['a', 'b']) {
      final notices = [
        {'id': 'n1', 'isRead': false},
        {'id': 'n2', 'isRead': false},
      ];
      await store.writeObject(account, 'approval:request', {
        'id': 'request',
        'title': 'before-$account',
      });
      await store.writeObject(account, OaLocalStore.bootstrapCacheKey, {
        'notifications': notices,
      });
      await store.writeObject(account, OaLocalStore.notificationPageCacheKey, {
        'items': notices,
      });
      await store.writeList(
        account,
        OaLocalStore.notificationsCacheKey,
        notices,
      );
    }
    f.repository = OaRepository(
      CollaborationClient(f.sessions),
      f.sessions,
      store,
    );
    f.server.listen(f.handle);
    return f;
  }

  Future<void> handle(HttpRequest request) async {
    paths.add(request.uri.path);
    methods.add(request.method);
    // Compare only synthetic fixture identities. Never print credentials/headers.
    identities.add(
      request.headers.value('Authorization') == 'Bearer fixture-old' &&
          request.headers.value('X-Terminal-Account-Id') == 'a',
    );
    final rawBody = await utf8.decoder.bind(request).join();
    bodies.add(
      rawBody.isEmpty
          ? {}
          : (jsonDecode(rawBody) as Map).cast<String, Object?>(),
    );
    await beforeReply(request);
    request.response.statusCode = status;
    request.response.headers.contentType = ContentType.json;
    request.response.write(
      jsonEncode({
        'id': 'request',
        'title': 'server-a',
        'items': [],
        'status': 'submitted',
        if (code.isNotEmpty) 'code': code,
      }),
    );
    await request.response.close();
  }

  Future<void> close() async {
    await server.close(force: true);
    await store.close();
  }
}

class _RealHttp extends HttpOverrides {}
