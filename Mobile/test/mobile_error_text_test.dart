import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/shared/errors/mobile_error_text.dart';

void main() {
  test('maps connection and timeout failures to compact offline copy', () {
    expect(
      mobileErrorText(
        DioException(
          requestOptions: RequestOptions(path: '/api/oa/bootstrap'),
          type: DioExceptionType.connectionError,
        ),
      ),
      '网络不可用，请检查连接后重试',
    );
    expect(mobileErrorText(TimeoutException('slow')), '网络连接超时，请检查网络后重试');
  });

  test(
    'maps session and server failures without exposing transport details',
    () {
      expect(
        mobileErrorText(
          DioException.badResponse(
            statusCode: 401,
            requestOptions: RequestOptions(path: '/api/oa/bootstrap'),
            response: Response<void>(
              requestOptions: RequestOptions(path: '/api/oa/bootstrap'),
              statusCode: 401,
            ),
          ),
        ),
        '登录已失效，请重新登录',
      );
      expect(
        mobileErrorText(
          Exception('https://example.test/api?token=secret failed'),
        ),
        '暂时无法加载，请稍后重试',
      );
    },
  );

  test('keeps the action while hiding raw request details', () {
    expect(
      mobileActionErrorText(
        '发送失败',
        Exception('https://example.test/api/messages?token=secret failed'),
      ),
      '发送失败：请稍后重试',
    );
    expect(
      mobileActionErrorText(
        '加载失败',
        Exception('connection failed at /api/im/sync/events'),
      ),
      '加载失败：请稍后重试',
    );
  });

  test(
    '405 exposes protocol incompatibility, not an offline or empty state',
    () {
      final request = RequestOptions(
        path: '/api/im/conversations/test/messages',
      );
      final error = DioException.badResponse(
        statusCode: 405,
        requestOptions: request,
        response: Response<Object?>(
          requestOptions: request,
          statusCode: 405,
          data: {'debug': 'private transport details'},
        ),
      );
      expect(mobileErrorText(error), '服务接口不兼容，请联系管理员');
      expect(mobileErrorText(error), isNot(contains('private')));
    },
  );
}
