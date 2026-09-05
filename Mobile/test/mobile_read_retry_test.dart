import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/mobile_read_retry.dart';

void main() {
  test('permanent HTTP errors and cancellation are never auto-retried', () {
    for (final status in [400, 401, 403, 404, 405, 409, 422]) {
      expect(mobileReadRetry(0, _responseError(status)), isNull);
    }
    expect(
      mobileReadRetry(
        0,
        DioException(
          requestOptions: RequestOptions(path: '/messages'),
          type: DioExceptionType.cancel,
        ),
      ),
      isNull,
    );
    expect(mobileReadRetry(0, StateError('invalid payload')), isNull);
  });

  test('transient reads retry at most twice without an unbounded loop', () {
    for (final error in [
      _responseError(408),
      _responseError(429),
      _responseError(500),
      const SocketException('offline'),
      TimeoutException('timeout'),
      DioException(
        requestOptions: RequestOptions(path: '/messages'),
        type: DioExceptionType.connectionError,
      ),
    ]) {
      expect(mobileReadRetry(0, error), const Duration(seconds: 1));
      expect(mobileReadRetry(1, error), const Duration(seconds: 2));
      expect(mobileReadRetry(2, error), isNull);
      expect(mobileReadRetry(10, error), isNull);
    }
  });
}

DioException _responseError(int status) {
  final request = RequestOptions(path: '/messages');
  return DioException.badResponse(
    statusCode: status,
    requestOptions: request,
    response: Response<void>(requestOptions: request, statusCode: status),
  );
}
