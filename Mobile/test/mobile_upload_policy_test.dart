import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/media/mobile_upload_policy.dart';

void main() {
  test('only static raster photo formats use local lossy compression', () {
    for (final type in const [
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/heic',
      'image/heif',
    ]) {
      expect(isMobileLocallyCompressibleImageType(type), isTrue);
    }
    expect(isMobileLocallyCompressibleImageType(' IMAGE/JPEG '), isTrue);
    expect(isMobileLocallyCompressibleImageType('image/gif'), isFalse);
    expect(isMobileLocallyCompressibleImageType('image/svg+xml'), isFalse);
    expect(isMobileLocallyCompressibleImageType('video/mp4'), isFalse);
  });

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

  test('original animated images use the 50 MiB inline image boundary', () {
    const limit = 50 * 1024 * 1024;
    expect(
      () => validateMobileUploadSourceLength(
        MobileUploadKind.chatOriginalImage,
        limit,
      ),
      returnsNormally,
    );
    expect(
      () => validateMobileUploadSourceLength(
        MobileUploadKind.chatOriginalImage,
        limit + 1,
      ),
      throwsA(
        isA<MobileUploadLimitException>().having(
          (error) => error.message,
          'message',
          'GIF 或矢量图片不能超过 50 MB，可改用文件发送',
        ),
      ),
    );
  });

  test('approval files accept exactly 20 MiB and reject the next byte', () {
    const limit = 20 * 1024 * 1024;
    expect(
      () => validateMobileUploadSourceLength(
        MobileUploadKind.approvalFile,
        limit,
      ),
      returnsNormally,
    );
    expect(
      () => validateMobileUploadSourceLength(
        MobileUploadKind.approvalFile,
        limit + 1,
      ),
      throwsA(
        isA<MobileUploadLimitException>().having(
          (error) => error.message,
          'message',
          '单个附件不能超过 20 MB',
        ),
      ),
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

  test('image processing failures use an actionable message', () {
    expect(
      mobileUploadErrorText(
        '图片发送失败',
        const MobileUploadProcessingException('图片处理失败，请重新选择或换一张图片'),
      ),
      '图片处理失败，请重新选择或换一张图片',
    );
  });
}
