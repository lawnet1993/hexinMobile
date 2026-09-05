import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../test_driver/session_refresh_probe.dart';

void main() {
  test(
    'refresh diagnostic excludes tokens, descriptions and unknown codes',
    () {
      final result = safeRefreshResponse(400, {
        'accessToken': 'private-token',
        'refresh_token': 'private-refresh',
        'error': 'private-code',
        'error_description': 'private-description',
        'device': 'private-device',
      });
      expect(result, {
        'status': 400,
        'errorCode': 'unrecognized',
        'hasAccessToken': true,
        'hasRefreshToken': true,
      });
      expect(jsonEncode(result), isNot(contains('private')));
      expect(
        safeRefreshResponse(401, {'error': 'invalid_client'})['errorCode'],
        'invalid_client',
      );
      expect(
        safeRefreshResponse(500, '<html>private</html>')['errorCode'],
        isNull,
      );
    },
  );
}
