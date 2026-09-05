import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/media/mobile_upload_policy.dart';

void main() {
  test('phone images may be compressed before their final upload limit', () {
    expect(
      () => validateMobileUploadSourceLength(
        MobileUploadKind.approvalImage,
        35 * 1024 * 1024,
      ),
      returnsNormally,
    );
    expect(
      () => validateMobileUploadSourceLength(
        MobileUploadKind.approvalFile,
        35 * 1024 * 1024,
      ),
      throwsA(isA<MobileUploadLimitException>()),
    );
  });

  test('chat files retain the server 512 MB boundary', () {
    expect(
      () => validateMobileUploadSourceLength(
        MobileUploadKind.chatFile,
        512 * 1024 * 1024,
      ),
      returnsNormally,
    );
    expect(
      () => validateMobileUploadSourceLength(
        MobileUploadKind.chatFile,
        512 * 1024 * 1024 + 1,
      ),
      throwsA(isA<MobileUploadLimitException>()),
    );
  });

  test('revoked platform file access is normalized', () async {
    await expectLater(
      withMobileFileAccess<void>(
        () => Future<void>.error(PlatformException(code: 'denied')),
      ),
      throwsA(isA<MobileUploadAccessException>()),
    );
    await expectLater(
      withMobileFileAccess<void>(
        () => Future<void>.error(FileSystemException('denied')),
      ),
      throwsA(isA<MobileUploadAccessException>()),
    );
    expect(
      mobileUploadErrorText('上传失败', const MobileUploadAccessException()),
      '无法访问所选文件，请重新选择或检查系统照片与文件权限',
    );
  });
}
