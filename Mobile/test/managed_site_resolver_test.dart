import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/workbench/data/managed_sites_repository.dart';

void main() {
  test(
    'authorized site falls back without forwarding terminal credentials',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requestedPaths = <String>[];
      final authorizationHeaders = <String?>[];
      server.listen((request) async {
        requestedPaths.add(request.uri.path);
        authorizationHeaders.add(
          request.headers.value(HttpHeaders.authorizationHeader),
        );
        request.response.statusCode = request.uri.path == '/primary'
            ? HttpStatus.serviceUnavailable
            : HttpStatus.unauthorized;
        await request.response.close();
      });

      final origin = 'http://${server.address.address}:${server.port}';
      final site = ManagedAccessSite(
        id: 'site-1',
        name: '数据中台',
        category: '数据',
        departmentName: '研发部',
        primaryDomain: server.address.address,
        loginUrl: '$origin/primary',
        backupDomains: server.address.address,
        backupLoginUrls: ['$origin/backup'],
      );

      try {
        final resolution = await ManagedSiteResolver().resolve(site);
        expect(resolution.uri.path, '/backup');
        expect(resolution.usedBackup, isTrue);
        expect(requestedPaths, ['/primary', '/backup']);
        expect(authorizationHeaders, everyElement(isNull));
      } finally {
        await server.close(force: true);
      }
    },
  );

  test('authorized site fails closed when every address is invalid', () async {
    const site = ManagedAccessSite(
      id: 'site-1',
      name: '数据中台',
      category: '数据',
      departmentName: '研发部',
      primaryDomain: '',
      loginUrl: 'javascript:alert(1)',
      backupDomains: '',
      backupLoginUrls: ['file:///etc/passwd'],
    );

    await expectLater(
      ManagedSiteResolver().resolve(site),
      throwsA(isA<ManagedSiteUnavailable>()),
    );
  });
}
