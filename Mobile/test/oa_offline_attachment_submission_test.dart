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

  test('offline attachment resumes upload before the queued approval is submitted', () async {
    HttpOverrides.global = _RealHttpOverrides();
    final directory = await Directory.systemTemp.createTemp(
      'oa-offline-attachment-',
    );
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final calls = <String>[];
    String uploadedBody = '';
    Map<String, Object?>? approvalBody;
    var attachmentAttempts = 0;

    server.listen((request) async {
      if (request.method == 'POST' &&
          request.uri.path == '/api/oa/attachments') {
        attachmentAttempts++;
        uploadedBody = utf8.decode(
          await request.fold<List<int>>(
            <int>[],
            (all, data) => all..addAll(data),
          ),
          allowMalformed: true,
        );
        calls.add('attachment:$attachmentAttempts');
        request.response.headers.contentType = ContentType.json;
        if (attachmentAttempts == 1) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          request.response.write(
            '{"message":"upstream https://private.invalid?token=synthetic-secret"}',
          );
        } else {
          request.response.statusCode = HttpStatus.created;
          request.response.write(
            jsonEncode({
              'id': 'server-attachment-1',
              'fileName': 'receipt.pdf',
              'contentType': 'application/pdf',
              'size': 15,
              'sha256': 'receipt-sha256',
              'isPreviewableImage': false,
            }),
          );
        }
        await request.response.close();
        return;
      }

      if (request.method == 'POST' &&
          request.uri.path == '/api/oa/approval-requests') {
        calls.add('approval');
        approvalBody = (jsonDecode(
          await utf8.decoder.bind(request).join(),
        ) as Map).cast<String, Object?>();
        request.response.headers.contentType = ContentType.json;
        request.response.write('{"id":"approval-1"}');
        await request.response.close();
        return;
      }

      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
    });

    FlutterSecureStorage.setMockInitialValues({});
    final sessionStore = SecureSessionStore();
    await sessionStore.saveSession(
      MobileSession(
        accessToken: 'token',
        deviceId: 'device-1',
        userId: 'member-1',
        displayName: '林晨',
        username: 'term.sh01',
        policySignatureKey: '',
        imApiUrl: '',
        oaApiUrl: 'http://${server.address.address}:${server.port}',
      ),
    );
    final localStore = OaLocalStore.withOptions(
      databaseFactoryFfi,
      () async => '${directory.path}/oa.db',
      const PlainImCacheCipher(),
    );
    final repository = OaRepository(
      CollaborationClient(sessionStore),
      sessionStore,
      localStore,
    );

    try {
      await expectLater(
        repository.submitApproval(
          applicationKey: 'expense',
          template: const OaApprovalTemplate(
            id: 'template-1',
            name: '报销审批',
            category: '财务',
            workflowKey: 'expense-flow',
            formSchemaJson:
                '{"fields":[{"id":"proof","label":"票据","type":"attachment"}]}',
          ),
          title: '离线票据补传',
          formData: const {'amount': 128.5},
          pendingAttachments: [
            OaLocalAttachment(
              id: 'local-attachment-1',
              fileName: 'receipt.pdf',
              contentType: 'application/pdf',
              bytes: utf8.encode('offline-receipt'),
              formFieldId: 'proof',
            ),
          ],
          allowOfflineQueue: true,
        ),
        throwsA(isA<OaSubmissionQueuedException>()),
      );

      final queued = (await repository.outbox()).single;
      expect(queued.lastError, '附件上传暂未完成（HTTP 503），将自动重试');
      expect(queued.lastError, isNot(contains('synthetic-secret')));
      expect(calls, ['attachment:1']);
      expect(queued.payload['attachmentIds'], isEmpty);
      expect(queued.payload['pendingAttachments'], hasLength(1));

      expect(await repository.retryOutbox(queued.id), 1);
      expect(calls, ['attachment:1', 'attachment:2', 'approval']);
      expect(uploadedBody, contains('filename="receipt.pdf"'));
      expect(uploadedBody, contains('offline-receipt'));
      expect(approvalBody?.containsKey('attachmentIds'), isFalse);
      expect(approvalBody?['attachmentBindings'], [
        {
          'attachmentId': 'server-attachment-1',
          'formFieldId': 'proof',
          'displayOrder': 0,
        },
      ]);
      final submittedForm =
          jsonDecode(approvalBody?['formDataJson']?.toString() ?? '{}') as Map;
      expect(
        (submittedForm['proof'] as List).single,
        containsPair('id', 'server-attachment-1'),
      );
      expect(approvalBody?.containsKey('pendingAttachments'), isFalse);
      expect(await repository.outbox(), isEmpty);
    } finally {
      await localStore.close();
      await server.close(force: true);
      await directory.delete(recursive: true);
      HttpOverrides.global = null;
    }
  });

  test(
    'permanent approval validation keeps every server field message',
    () async {
      HttpOverrides.global = _RealHttpOverrides();
      final directory = await Directory.systemTemp.createTemp(
        'oa-validation-outbox-',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);

      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.method == 'POST' &&
            request.uri.path == '/api/oa/approval-requests') {
          await request.drain<void>();
          request.response.statusCode = HttpStatus.badRequest;
          request.response.write(
            jsonEncode({
              'message': 'Approval form validation failed.',
              'errors': [
                {'target': 'leaveType', 'message': '请选择请假类型。'},
                {'target': 'reason', 'message': '请填写请假事由。'},
              ],
            }),
          );
        } else {
          request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });

      FlutterSecureStorage.setMockInitialValues({});
      final sessionStore = SecureSessionStore();
      await sessionStore.saveSession(
        MobileSession(
          accessToken: 'token',
          deviceId: 'device-1',
          userId: 'member-1',
          displayName: '林晨',
          username: 'term.sh01',
          policySignatureKey: '',
          imApiUrl: '',
          oaApiUrl: 'http://${server.address.address}:${server.port}',
        ),
      );
      final localStore = OaLocalStore.withOptions(
        databaseFactoryFfi,
        () async => '${directory.path}/oa.db',
        const PlainImCacheCipher(),
      );
      final repository = OaRepository(
        CollaborationClient(sessionStore),
        sessionStore,
        localStore,
      );

      try {
        await expectLater(
          repository.submitApproval(
            applicationKey: 'attendance.leave',
            template: const OaApprovalTemplate(
              id: 'template-leave',
              name: '请假审批',
              category: '考勤',
              workflowKey: 'attendance.leave',
            ),
            title: 'AI-UAT-请假审批',
            formData: const {'leaveType': '', 'reason': ''},
          ),
          throwsA(isA<DioException>()),
        );

        final failed = (await repository.outbox()).single;
        expect(failed.state, 'failed');
        expect(
          failed.lastError,
          'Approval form validation failed.\n'
          '请选择请假类型。\n'
          '请填写请假事由。',
        );
      } finally {
        await localStore.close();
        await server.close(force: true);
        await directory.delete(recursive: true);
        HttpOverrides.global = null;
      }
    },
  );
}

final class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionTimeout = const Duration(seconds: 5);
    return client;
  }
}
