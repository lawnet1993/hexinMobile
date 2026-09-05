import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_upload_diagnostics.dart';

void main() {
  const trace = '00-1234567890abcdef1234567890abcdef-1234567890abcdef-01';
  const secret = 'private-fixture-not-for-logs';
  DioException error({
    String path = '/api/im/upload/video',
    Object? body,
    Map<String, List<String>>? headers,
    bool network = false,
  }) {
    final request = RequestOptions(
      path: path,
      headers: {
        'Authorization': secret,
        'Cookie': secret,
        'X-Device-Id': secret,
      },
      data: FormData.fromMap({
        'clientMessageId': secret,
        'caption': secret,
        secret: secret,
        'file': MultipartFile.fromBytes([1, 2, 3, 4], filename: secret),
      }),
    );
    return DioException(
      requestOptions: request,
      type: network
          ? DioExceptionType.connectionTimeout
          : DioExceptionType.badResponse,
      message: secret,
      response: network
          ? null
          : Response<Object?>(
              requestOptions: request,
              statusCode: 500,
              data: body,
              headers: Headers.fromMap(
                headers ??
                    {
                      'content-type': ['application/problem+json'],
                    },
              ),
            ),
    );
  }

  test('disabled by default and ignores non-upload errors', () {
    final lines = <String>[];
    ImUploadDiagnostics(write: lines.add).failure(error());
    final enabled = ImUploadDiagnostics(enabled: true, write: lines.add);
    enabled.failure(StateError(secret));
    enabled.failure(error(path: '/api/client/login'));
    enabled.failure(error(path: '/api/im/conversations/fixture/messages'));
    expect(lines, isEmpty);
  });

  test(
    'fixed field allowlist excludes bodies, credentials, names and addresses',
    () {
      final lines = <String>[];
      ImUploadDiagnostics(enabled: true, write: lines.add).failure(
        error(
          path: '/api/im/conversations/$secret/images?token=$secret',
          body: {
            'code': secret,
            'message': secret,
            'detail': 'https://$secret/file?token=$secret',
            'password': secret,
            'traceId': trace,
            'attachments': [secret],
          },
          headers: {
            'content-type': ['application/problem+json; secret=$secret'],
            'x-request-id': ['12345678-1234-1234-1234-123456789abc'],
            'x-correlation-id': [secret],
            'authorization': [secret],
            'set-cookie': [secret],
            'location': ['https://$secret'],
          },
        ),
      );
      expect(lines.single, isNot(contains(secret)));
      final record =
          jsonDecode(lines.single.split('MOBILE_IM_UPLOAD ').last) as Map;
      expect(record.keys.toSet(), {
        'sampledAt',
        'operation',
        'httpStatus',
        'failureType',
        'requestBody',
        'formFields',
        'fileBytes',
        'responseType',
        'bodyShape',
        'errorCode',
        'errorSignals',
        'requestId',
        'correlationId',
        'traceparent',
        'bodyTraceId',
      });
      expect(record['operation'], 'image_send');
      expect(record['formFields'], ['clientMessageId', 'caption', 'file']);
      expect(record['fileBytes'], [4]);
      expect(record['bodyTraceId'], trace);
      expect(record['requestId'], '12345678-1234-1234-1234-123456789abc');
      expect(record['correlationId'], isNull);
      expect(record['errorCode'], isNull);
      expect(record['responseType'], 'json');
    },
  );

  for (final candidate in [
    secret,
    'Bearer $secret',
    'https://$secret',
    'a' * 81,
    '12345678-1234-1234-1234-123456789abc\n$secret',
    'eyJhbGciOiJIUzI1NiJ9.fixture.signature',
  ]) {
    test('rejects non-correlation value ${candidate.length}', () {
      final lines = <String>[];
      ImUploadDiagnostics(
        enabled: true,
        write: lines.add,
      ).failure(error(body: {'traceId': candidate}));
      final record =
          jsonDecode(lines.single.split('MOBILE_IM_UPLOAD ').last) as Map;
      expect(record['bodyTraceId'], isNull);
      expect(lines.single, isNot(contains(candidate)));
    });
  }

  test('classifies known storage phrase without leaking raw details', () {
    final lines = <String>[];
    ImUploadDiagnostics(enabled: true, write: lines.add).failure(
      error(
        body: {
          'code': 'NoSuchBucket',
          'message': 'The specified bucket does not exist: $secret',
          'traceId': '0HNFABC123456:00000001',
        },
      ),
    );
    final record =
        jsonDecode(lines.single.split('MOBILE_IM_UPLOAD ').last) as Map;
    expect(record['errorCode'], 'NoSuchBucket');
    expect(record['errorSignals'], ['missing_bucket']);
    expect(record['bodyTraceId'], '0HNFABC123456:00000001');
    expect(lines.single, isNot(contains(secret)));
  });

  test('network error remains distinct from HTTP server response', () {
    final lines = <String>[];
    ImUploadDiagnostics(
      enabled: true,
      write: lines.add,
    ).failure(error(network: true));
    final record =
        jsonDecode(lines.single.split('MOBILE_IM_UPLOAD ').last) as Map;
    expect(record['httpStatus'], isNull);
    expect(record['failureType'], 'connectionTimeout');
    expect(record['bodyShape'], 'empty');
  });

  test('repeated headers do not replace the original upload failure', () {
    final lines = <String>[];
    ImUploadDiagnostics(enabled: true, write: lines.add).failure(
      error(
        headers: {
          'content-type': ['application/json', 'application/json'],
          'x-request-id': [secret, secret],
        },
      ),
    );
    expect(lines, hasLength(1));
    expect(lines.single, isNot(contains(secret)));
  });

  test('diagnostic sink failure cannot change queue retry behavior', () {
    expect(
      () => ImUploadDiagnostics(
        enabled: true,
        write: (_) {
          throw StateError(secret);
        },
      ).failure(error()),
      returnsNormally,
    );
  });
}
