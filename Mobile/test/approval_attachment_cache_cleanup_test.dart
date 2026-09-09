import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/todos/presentation/approval_detail_page.dart';
import 'package:path/path.dart' as path;

void main() {
  test(
    'removes stale OA handoff, download and object-cache directories',
    () async {
      final temporaryRoot = await Directory.systemTemp.createTemp(
        'oa-handoff-cleanup-test-',
      );
      final account = Directory(
        path.join(temporaryRoot.path, 'oa-attachments', 'account'),
      );
      final stale = await Directory(path.join(account.path, 'open-stale'))
          .create(recursive: true);
      final fresh = await Directory(path.join(account.path, 'open-fresh'))
          .create(recursive: true);
      final staleCache = await Directory(path.join(account.path, 'cache-stale'))
          .create(recursive: true);
      final staleDownload = await Directory(
        path.join(account.path, 'download-stale'),
      ).create(recursive: true);
      final unrelated = await Directory(path.join(account.path, 'keep-data'))
          .create(recursive: true);
      final staleFile = await File(path.join(stale.path, 'old.pdf'))
          .writeAsBytes([1]);
      final freshFile = await File(path.join(fresh.path, 'current.pdf'))
          .writeAsBytes([2]);
      final staleCacheFile = await File(path.join(staleCache.path, 'old.docx'))
          .writeAsBytes([3]);
      final staleDownloadFile = await File(
        path.join(staleDownload.path, 'partial.tmp'),
      ).writeAsBytes([4]);
      await staleFile.setLastModified(DateTime(2026, 9, 7, 8));
      await freshFile.setLastModified(DateTime(2026, 9, 9, 7, 30));
      await staleCacheFile.setLastModified(DateTime(2026, 9, 7, 8));
      await staleDownloadFile.setLastModified(DateTime(2026, 9, 7, 8));

      try {
        await cleanupStaleApprovalAttachmentHandoffs(
          temporaryRoot,
          now: DateTime(2026, 9, 9, 8),
        );

        expect(await stale.exists(), isFalse);
        expect(await staleCache.exists(), isFalse);
        expect(await staleDownload.exists(), isFalse);
        expect(await fresh.exists(), isTrue);
        expect(await unrelated.exists(), isTrue);
      } finally {
        await temporaryRoot.delete(recursive: true);
      }
    },
  );
}
