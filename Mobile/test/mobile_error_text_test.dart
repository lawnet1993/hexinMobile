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
}
