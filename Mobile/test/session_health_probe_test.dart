import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../test_driver/session_health_probe.dart';

void main() {
  test('token time hints never include identity or secret fields', () {
    final payload = base64Url.encode(
      utf8.encode(
        jsonEncode({
          'iat': 1000,
          'nbf': 1000,
          'exp': 2000,
          'sub': 'private-account',
          'device': 'private-device',
          'fingerprint': 'private-fingerprint',
          'url': 'private-attachment',
        }),
      ),
    );
    final result = tokenTimeHints('fixture.$payload.private-signature');
    expect(result, {
      'verified': false,
      'iat': '1970-01-01T00:16:40.000Z',
      'nbf': '1970-01-01T00:16:40.000Z',
      'exp': '1970-01-01T00:33:20.000Z',
      'available': true,
    });
    expect(jsonEncode(result), isNot(contains('private')));
  });
  test('opaque, malformed and nonnumeric claims are not expiry evidence', () {
    for (final token in [
      'opaque',
      'x.?.y',
      'x.${base64Url.encode(utf8.encode('{"exp":"private"}'))}.y',
    ]) {
      expect(tokenTimeHints(token)['available'], false);
    }
  });
}
