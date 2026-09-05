import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';

/// Bound automatic read retries. Permanent protocol/auth failures need user
/// action, not Riverpod's default ten retries. Manual retry remains available.
Duration? mobileReadRetry(int retryCount, Object error) {
  if (retryCount >= 2) return null;
  if (error is DioException) {
    if (error.type == DioExceptionType.cancel) return null;
    final status = error.response?.statusCode;
    if (status != null) {
      return status == 408 || status == 429 || status >= 500
          ? Duration(seconds: retryCount + 1)
          : null;
    }
    return switch (error.type) {
      DioExceptionType.connectionError ||
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout => Duration(seconds: retryCount + 1),
      _ => null,
    };
  }
  if (error is SocketException || error is TimeoutException) {
    return Duration(seconds: retryCount + 1);
  }
  return null;
}
