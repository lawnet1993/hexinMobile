import 'dart:async';
import 'dart:io';

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

  test('maps full storage without exposing a local attachment path', () {
    final error = FileSystemException(
      'write failed',
      r'C:\Users\fixture\secret\attachment.part',
      const OSError('No space left on device', 28),
    );

    final text = mobileActionErrorText('媒体打开失败', error);

    expect(text, '媒体打开失败：设备存储空间不足，请清理后重试');
    expect(text, isNot(contains('attachment.part')));
    expect(text, isNot(contains('secret')));
  });

  test('unwraps a Dio file write failure into the full storage message', () {
    final request = RequestOptions(path: '/api/im/messages/test/attachment');
    final error = DioException(
      requestOptions: request,
      type: DioExceptionType.unknown,
      error: const FileSystemException(
        'Cannot copy file',
        '/private/cache/attachment.part',
        OSError('No space left on device', 28),
      ),
    );

    final text = mobileActionErrorText('附件打开失败', error);

    expect(text, '附件打开失败：设备存储空间不足，请清理后重试');
    expect(text, isNot(contains('/private/cache')));
  });

  test('hides raw local paths for other file system failures', () {
    final error = FileSystemException(
      'permission denied',
      r'C:\Users\fixture\secret\attachment.part',
      const OSError('Access is denied', 5),
    );

    final text = mobileErrorText(error);

    expect(text, '无法访问本地文件，请检查系统权限或存储空间后重试');
    expect(text, isNot(contains('attachment.part')));
  });
}
