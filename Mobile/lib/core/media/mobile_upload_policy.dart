import 'dart:io';

import 'package:flutter/services.dart';

import '../../shared/errors/mobile_error_text.dart';

enum MobileUploadKind {
  avatar,
  chatImage,
  chatFile,
  chatVideo,
  chatAudio,
  approvalImage,
  approvalFile,
}

final class MobileUploadAccessException implements Exception {
  const MobileUploadAccessException();
}

final class MobileUploadLimitException implements Exception {
  const MobileUploadLimitException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Runs one system-picker or selected-file read operation and normalizes
/// revoked URI/file-provider access without leaking the provider path.
Future<T> withMobileFileAccess<T>(Future<T> Function() operation) async {
  try {
    return await operation();
  } on PlatformException {
    throw const MobileUploadAccessException();
  } on FileSystemException {
    throw const MobileUploadAccessException();
  }
}

Stream<List<int>> withMobileFileStreamAccess(Stream<List<int>> source) async* {
  try {
    await for (final chunk in source) {
      yield chunk;
    }
  } on PlatformException {
    throw const MobileUploadAccessException();
  } on FileSystemException {
    throw const MobileUploadAccessException();
  }
}

void validateMobileUploadSourceLength(MobileUploadKind kind, int length) {
  if (length <= 0) return;
  final limit = switch (kind) {
    MobileUploadKind.avatar ||
    MobileUploadKind.chatImage ||
    MobileUploadKind.approvalImage => 80 * 1024 * 1024,
    MobileUploadKind.approvalFile => 20 * 1024 * 1024,
    MobileUploadKind.chatFile ||
    MobileUploadKind.chatVideo ||
    MobileUploadKind.chatAudio => 512 * 1024 * 1024,
  };
  if (length <= limit) return;
  final message = switch (kind) {
    MobileUploadKind.avatar => '头像原图不能超过 80 MB',
    MobileUploadKind.chatImage => '单张图片原图不能超过 80 MB',
    MobileUploadKind.approvalImage => '图片原图不能超过 80 MB',
    MobileUploadKind.approvalFile => '单个附件不能超过 20 MB',
    MobileUploadKind.chatFile => '文件不能超过 512 MB',
    MobileUploadKind.chatVideo ||
    MobileUploadKind.chatAudio => '媒体文件不能超过 512 MB',
  };
  throw MobileUploadLimitException(message);
}

String mobileUploadErrorText(String action, Object error) {
  if (error is MobileUploadAccessException) {
    return '无法访问所选文件，请重新选择或检查系统照片与文件权限';
  }
  if (error case MobileUploadLimitException(:final message)) return message;
  return mobileActionErrorText(action, error);
}
