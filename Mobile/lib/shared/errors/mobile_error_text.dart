import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

String mobileErrorText(Object error, {String fallback = '暂时无法加载，请稍后重试'}) {
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status != null) {
      if (status == 401) return '登录已失效，请重新登录';
      if (status == 403) return '当前账号暂无权限';
      if (status == 404) return '请求的数据不存在或已被移除';
      if (status == 405) return '服务接口不兼容，请联系管理员';
      if (status == 408 || status == 429 || status >= 500) {
        return '服务暂时不可用，请稍后重试';
      }
      return fallback;
    }
    final cause = error.error;
    if (cause is FileSystemException) return mobileErrorText(cause);
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => '网络连接超时，请检查网络后重试',
      DioExceptionType.connectionError => '网络不可用，请检查连接后重试',
      DioExceptionType.cancel => '请求已取消',
      _ => fallback,
    };
  }
  if (error is SocketException) return '网络不可用，请检查连接后重试';
  if (error is TimeoutException) return '网络连接超时，请检查网络后重试';
  if (error is FileSystemException) {
    final osCode = error.osError?.errorCode;
    final details = '${error.message} ${error.osError?.message ?? ''}'
        .toLowerCase();
    if (osCode == 28 ||
        osCode == 112 ||
        details.contains('no space left on device') ||
        details.contains('disk is full') ||
        details.contains('not enough space')) {
      return '设备存储空间不足，请清理后重试';
    }
    return '无法访问本地文件，请检查系统权限或存储空间后重试';
  }

  final message = error.toString().replaceFirst('Exception: ', '').trim();
  final normalized = message.toLowerCase();
  if (message.isEmpty ||
      message.length > 80 ||
      message.contains('http://') ||
      message.contains('https://') ||
      message.contains('/api/') ||
      normalized.contains('token') ||
      normalized.contains('dioexception') ||
      normalized.contains('socketexception') ||
      normalized.contains('requestoptions') ||
      normalized.contains('stack trace') ||
      message.contains('\n')) {
    return fallback;
  }
  return message;
}

String mobileActionErrorText(
  String action,
  Object error, {
  String fallback = '请稍后重试',
}) => '$action：${mobileErrorText(error, fallback: fallback)}';
