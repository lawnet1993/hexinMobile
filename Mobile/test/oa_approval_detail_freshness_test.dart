import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/im_cache_cipher.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/oa_local_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'approval detail returns its cached snapshot without a network wait',
    () async {
      HttpOverrides.global = _RealHttpOverrides();
      final directory = await Directory.systemTemp.createTemp(
        'oa-detail-cache-first-',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requestCount = 0;
      server.listen((request) async {
        requestCount += 1;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_requestJson(status: 'approved')));
        await request.response.close();
      });
      final fixture = await _fixture(
        directory,
        oaApiUrl: 'http://${server.address.address}:${server.port}',
      );
      await fixture.store.writeObject(
        'member-1',
        'approval:approval-1',
        _requestJson(status: 'pending'),
      );

      try {
        final request = await fixture.repository.approvalRequestCacheFirst(
          'approval-1',
        );
        expect(request.status, 'pending');
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(requestCount, 0);
      } finally {
        await fixture.store.close();
        await server.close(force: true);
        await directory.delete(recursive: true);
        HttpOverrides.global = null;
      }
    },
  );

  test(
    'approval detail replaces stale cache with the current server state',
    () async {
      HttpOverrides.global = _RealHttpOverrides();
      final directory = await Directory.systemTemp.createTemp(
        'oa-detail-fresh-',
      );
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      Uri? requestedUri;
      server.listen((request) async {
        requestedUri = request.uri;
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode(_requestJson(status: 'approved')));
        await request.response.close();
      });
      final fixture = await _fixture(
        directory,
        oaApiUrl: 'http://${server.address.address}:${server.port}',
      );
      await fixture.store.writeObject(
        'member-1',
        'approval:approval-1',
        _requestJson(status: 'pending'),
      );

      try {
        final request = await fixture.repository.approvalRequestNetworkFirst(
          'approval-1',
        );
        expect(requestedUri?.path, '/api/oa/approval-requests/approval-1');
        expect(request.status, 'approved');
        expect(
          (await fixture.store.readObject(
            'member-1',
            'approval:approval-1',
          ))?['status'],
          'approved',
        );
      } finally {
        await fixture.store.close();
        await server.close(force: true);
        await directory.delete(recursive: true);
        HttpOverrides.global = null;
      }
    },
  );

  test('approval detail keeps the last server state while offline', () async {
    HttpOverrides.global = _RealHttpOverrides();
    final directory = await Directory.systemTemp.createTemp(
      'oa-detail-offline-',
    );
    final fixture = await _fixture(directory, oaApiUrl: 'http://127.0.0.1:9');
    await fixture.store.writeObject(
      'member-1',
      'approval:approval-1',
      _requestJson(status: 'pending'),
    );

    try {
      final request = await fixture.repository.approvalRequestNetworkFirst(
        'approval-1',
      );
      expect(request.status, 'pending');
    } finally {
      await fixture.store.close();
      await directory.delete(recursive: true);
      HttpOverrides.global = null;
    }
  });
}

Future<({OaRepository repository, OaLocalStore store})> _fixture(
  Directory directory, {
  required String oaApiUrl,
}) async {
  FlutterSecureStorage.setMockInitialValues({});
  final sessionStore = SecureSessionStore();
  await sessionStore.saveSession(
    MobileSession(
      accessToken: 'token',
      deviceId: 'device-1',
      userId: 'member-1',
      displayName: '测试终端',
      username: 'qa.term',
      policySignatureKey: '',
      imApiUrl: '',
      oaApiUrl: oaApiUrl,
    ),
  );
  final store = OaLocalStore.withOptions(
    databaseFactoryFfi,
    () async => '${directory.path}/oa.db',
    const PlainImCacheCipher(),
  );
  return (
    repository: OaRepository(
      CollaborationClient(sessionStore),
      sessionStore,
      store,
    ),
    store: store,
  );
}

Map<String, Object?> _requestJson({required String status}) => {
  'id': 'approval-1',
  'requesterId': 'member-1',
  'title': 'AI-UAT-审批状态校准',
  'formDataJson': '{}',
  'formSchemaSnapshotJson': '{}',
  'status': status,
  'createdAt': '2026-09-01T06:39:00Z',
  'updatedAt': '2026-09-01T07:00:00Z',
  'requesterName': '测试发起人',
  'requesterDepartmentName': '测试部门',
  'templateName': '测试审批',
  'templateCategory': '财务',
  'applicationKey': 'test.approval',
  'allowedActions': <String>[],
  'tasks': <Object?>[],
  'actions': <Object?>[],
  'attachments': <Object?>[],
  'ccs': <Object?>[],
};

final class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionTimeout = const Duration(seconds: 2);
    return client;
  }
}
