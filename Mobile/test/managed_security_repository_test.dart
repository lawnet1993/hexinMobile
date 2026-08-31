import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/security/managed_security_repository.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('managed policy uses the desktop HMAC envelope contract', () async {
    HttpOverrides.global = _RealHttpOverrides();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    const payload = '{"enabled":true}';
    final signature = Hmac(
      sha256,
      utf8.encode('policy-secret'),
    ).convert(utf8.encode(payload)).toString();
    server.listen((request) async {
      expect(request.uri.path, '/api/client/policies/current');
      expect(request.uri.queryParameters['deviceId'], 'device-1');
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'policyVersion': '2026.08.25.1',
          'signatureAlgorithm': 'HMAC-SHA256-HEX',
          'signature': signature,
          'payloadJson': payload,
          'publishedAt': '2026-08-25T00:00:00Z',
        }),
      );
      await request.response.close();
    });
    final fixture = await _fixture(server);
    try {
      final status = await fixture.repository.fetchPolicy();
      expect(status.enabled, isTrue);
      expect(status.signatureVerified, isTrue);
      expect(status.policyVersion, '2026.08.25.1');
    } finally {
      await server.close(force: true);
    }
  });

  test('tampered managed policy is rejected before use', () async {
    HttpOverrides.global = _RealHttpOverrides();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'policyVersion': 'tampered',
          'signatureAlgorithm': 'HMAC-SHA256-HEX',
          'signature': '00',
          'payloadJson': '{"enabled":true}',
          'publishedAt': '2026-08-25T00:00:00Z',
        }),
      );
      await request.response.close();
    });
    final fixture = await _fixture(server);
    try {
      await expectLater(
        fixture.repository.fetchPolicy(),
        throwsA(isA<FormatException>()),
      );
    } finally {
      await server.close(force: true);
    }
  });

  test(
    'terminal commands and completion use desktop-compatible routes',
    () async {
      HttpOverrides.global = _RealHttpOverrides();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      Map<String, Object?>? completion;
      server.listen((request) async {
        request.response.headers.contentType = ContentType.json;
        if (request.method == 'GET') {
          expect(request.uri.path, '/api/client/commands');
          request.response.write(
            '[{"id":"command-1","commandType":3,"durationSeconds":0,'
            '"expiresAt":"2026-08-26T00:00:00Z"}]',
          );
        } else {
          expect(request.uri.path, '/api/client/commands/command-1/complete');
          completion = (jsonDecode(
            await utf8.decoder.bind(request).join(),
          ) as Map).cast<String, Object?>();
          request.response.statusCode = HttpStatus.noContent;
        }
        await request.response.close();
      });
      final fixture = await _fixture(server);
      try {
        final commands = await fixture.repository.fetchCommands();
        expect(commands.single.commandType, 3);
        await fixture.repository.completeCommand(
          commands.single.id,
          succeeded: true,
          resultMessage: 'Android 终端已收到强制下线指令。',
        );
        expect(completion?['deviceId'], 'device-1');
        expect(completion?['succeeded'], isTrue);
      } finally {
        await server.close(force: true);
      }
    },
  );
}

Future<_Fixture> _fixture(HttpServer server) async {
  FlutterSecureStorage.setMockInitialValues({});
  final store = SecureSessionStore();
  await store.saveSession(
    const MobileSession(
      accessToken: 'token',
      deviceId: 'device-1',
      userId: 'member-1',
      displayName: '测试终端',
      username: 'qa.term',
      policySignatureKey: 'policy-secret',
      imApiUrl: '',
      oaApiUrl: '',
    ),
  );
  final dio = Dio(
    BaseOptions(baseUrl: 'http://${server.address.address}:${server.port}'),
  );
  return _Fixture(ManagedSecurityRepository(dio, store));
}

final class _Fixture {
  const _Fixture(this.repository);
  final ManagedSecurityRepository repository;
}

final class _RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context)..findProxy = (_) => 'DIRECT';
}
