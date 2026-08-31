import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';

void main() {
  group('collaborationOrigin', () {
    test('strips a service-scoped IM base URL', () {
      expect(
        collaborationOrigin('http://example.test/api/im', '/api/im'),
        'http://example.test',
      );
    });

    test('strips a service-scoped OA base URL and trailing slash', () {
      expect(
        collaborationOrigin('https://example.test/gateway/api/oa/', '/api/oa'),
        'https://example.test/gateway',
      );
    });

    test('keeps an origin-only deployment URL', () {
      expect(
        collaborationOrigin('https://example.test/', '/api/im'),
        'https://example.test',
      );
    });
  });
}
