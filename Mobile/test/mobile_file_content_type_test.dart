import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/media/mobile_file_content_type.dart';

void main() {
  test('office files use previewable standard content types', () {
    expect(mobileFileContentType('doc'), 'application/msword');
    expect(
      mobileFileContentType('.DOCX'),
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    );
    expect(mobileFileContentType('xls'), 'application/vnd.ms-excel');
    expect(
      mobileFileContentType('xlsx'),
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
    expect(mobileFileContentType('ppt'), 'application/vnd.ms-powerpoint');
    expect(
      mobileFileContentType('pptx'),
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    );
  });

  test('common files keep useful types and unknown files fail safely', () {
    expect(mobileFileContentType('pdf'), 'application/pdf');
    expect(mobileFileContentType('csv'), 'text/csv');
    expect(mobileFileContentType('7z'), 'application/x-7z-compressed');
    expect(mobileFileContentType('unknown'), 'application/octet-stream');
    expect(mobileFileContentType(null), 'application/octet-stream');
  });

  test(
    'extensionless image headers recover a safe image content type',
    () async {
      final cases = <String, List<int>>{
        'image/jpeg': [0xFF, 0xD8, 0xFF, 0xE0],
        'image/png': [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
        'image/webp': [...'RIFF'.codeUnits, 0, 0, 0, 0, ...'WEBP'.codeUnits],
        'image/gif': 'GIF89a'.codeUnits,
        'image/heic': [0, 0, 0, 24, ...'ftyp'.codeUnits, ...'heic'.codeUnits],
        'image/svg+xml': '<svg xmlns="http://www.w3.org/2000/svg"/>'.codeUnits,
      };
      for (final entry in cases.entries) {
        expect(
          await resolveMobileFileContentType(
            fileName: 'shared-image',
            openRead: () => Stream.value(entry.value),
          ),
          entry.key,
        );
      }
    },
  );

  test(
    'known extension avoids source I/O and unknown data stays binary',
    () async {
      var opened = false;
      expect(
        await resolveMobileFileContentType(
          fileName: 'photo.JPG',
          openRead: () {
            opened = true;
            return const Stream.empty();
          },
        ),
        'image/jpeg',
      );
      expect(opened, isFalse);
      expect(
        await resolveMobileFileContentType(
          fileName: 'attachment',
          openRead: () => Stream.value(const [1, 2, 3, 4]),
        ),
        'application/octet-stream',
      );
    },
  );
}
