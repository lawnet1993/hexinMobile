import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  test(
    'contact search sends the desktop-compatible full account payload',
    () async {
      HttpOverrides.global = _RealHttpOverrides();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      Map<String, Object?>? body;
      server.listen((request) async {
        body = (jsonDecode(await utf8.decoder.bind(request).join()) as Map)
            .cast<String, Object?>();
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          jsonEncode({
            'id': 'member-2',
            'userName': 'term.qa02',
            'displayName': '测试成员',
            'isFriend': false,
          }),
        );
        await request.response.close();
      });
      final fixture = await _fixture(server);
      try {
        final result = await fixture.repository.searchMembers(' term.qa02 ');
        expect(body, {'userName': 'term.qa02'});
        expect(result.single.username, 'term.qa02');
        expect(result.single.isFriend, isFalse);
      } finally {
        await server.close(force: true);
      }
    },
  );

  test(
    'successful friend request is not reported failed when refresh is offline',
    () async {
      HttpOverrides.global = _RealHttpOverrides();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var mutations = 0;
      server.listen((request) async {
        if (request.uri.path == '/api/im/friends/applications') {
          mutations++;
          final body = (jsonDecode(
            await utf8.decoder.bind(request).join(),
          ) as Map).cast<String, Object?>();
          expect(body['targetMemberId'], 'member-2');
          expect(body['greeting'], '你好');
          request.response.statusCode = HttpStatus.noContent;
        } else {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          request.response.write('{"message":"refresh unavailable"}');
        }
        await request.response.close();
      });
      final fixture = await _fixture(server);
      try {
        await expectLater(
          fixture.repository.requestFriend('member-2', ' 你好 '),
          completes,
        );
        expect(mutations, 1);
      } finally {
        await server.close(force: true);
      }
    },
  );

  test('unknown terminal account produces an empty search result', () async {
    HttpOverrides.global = _RealHttpOverrides();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      await request.drain<void>();
      request.response.statusCode = HttpStatus.notFound;
      request.response.write(
        '{"message":"The requested IM resource was not found."}',
      );
      await request.response.close();
    });
    final fixture = await _fixture(server);
    try {
      await expectLater(
        fixture.repository.searchMembers('unknown.account'),
        completion(isEmpty),
      );
    } finally {
      await server.close(force: true);
    }
  });

  test('message read receipt parses the desktop object contract', () async {
    HttpOverrides.global = _RealHttpOverrides();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      expect(request.uri.path, '/api/im/messages/message-1/read-receipts');
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'conversationId': 'conversation-1',
          'messageId': 'message-1',
          'sequence': 8,
          'readCount': 1,
          'totalRecipientCount': 2,
          'isReadByAll': false,
          'peerRead': true,
          'readers': [
            {
              'memberId': 'member-2',
              'userName': 'term.qa02',
              'displayName': '测试成员',
              'role': 'member',
              'readAt': '2026-08-25T08:30:00Z',
            },
          ],
        }),
      );
      await request.response.close();
    });
    final fixture = await _fixture(server);
    try {
      final receipt = await fixture.repository.messageReadReceipts('message-1');
      expect(receipt.readCount, 1);
      expect(receipt.totalRecipientCount, 2);
      expect(receipt.isReadByAll, isFalse);
      expect(receipt.readers.single.displayName, '测试成员');
      expect(receipt.readers.single.username, 'term.qa02');
    } finally {
      await server.close(force: true);
    }
  });
}

Future<_Fixture> _fixture(HttpServer server) async {
  FlutterSecureStorage.setMockInitialValues({});
  final sessionStore = SecureSessionStore();
  await sessionStore.saveSession(
    MobileSession(
      accessToken: 'token',
      deviceId: 'device-1',
      userId: 'member-1',
      displayName: '当前成员',
      username: 'term.qa01',
      policySignatureKey: '',
      imApiUrl: 'http://${server.address.address}:${server.port}',
      oaApiUrl: '',
    ),
  );
  return _Fixture(
    ImRepository(
      CollaborationClient(sessionStore),
      sessionStore,
      ImLocalStore(),
    ),
  );
}

final class _Fixture {
  const _Fixture(this.repository);
  final ImRepository repository;
}

final class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}
