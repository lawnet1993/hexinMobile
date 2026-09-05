import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_outbox_file_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('queued media is encrypted, authenticated and account scoped', () async {
    final directory = await Directory.systemTemp.createTemp(
      'im-outbox-file-store-',
    );
    final store = ImOutboxFileStore(
      keyLoader: (accountId) async => List<int>.generate(
        32,
        (index) =>
            (index + accountId.codeUnits.fold<int>(0, (a, b) => a + b)) % 256,
      ),
      directoryLoader: () async => directory,
    );
    final clear = Uint8List.fromList('AI-UAT-private-image-payload'.codeUnits);

    try {
      final stored = await store.writeBytes(
        accountId: 'account-a',
        clientMessageId: 'client-1',
        role: 'image',
        fileName: 'private-photo.jpg',
        contentType: 'image/jpeg',
        bytes: clear,
      );
      final files = await directory
          .list(recursive: true)
          .where((entity) => entity is File && entity.path.endsWith('.imq'))
          .cast<File>()
          .toList();
      expect(files, hasLength(1));
      final encrypted = await files.single.readAsBytes();
      expect(_contains(encrypted, clear), isFalse);
      expect(
        String.fromCharCodes(encrypted).contains('private-photo.jpg'),
        isFalse,
      );
      expect(
        await store.readBytes(
          accountId: 'account-a',
          clientMessageId: 'client-1',
          file: stored,
        ),
        clear,
      );
      await expectLater(
        store.readBytes(
          accountId: 'account-b',
          clientMessageId: 'client-1',
          file: stored,
        ),
        throwsStateError,
      );

      encrypted[encrypted.length - 1] ^= 1;
      await files.single.writeAsBytes(encrypted, flush: true);
      await expectLater(
        store.readBytes(
          accountId: 'account-a',
          clientMessageId: 'client-1',
          file: stored,
        ),
        throwsA(anything),
      );
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test(
    'large payloads are copied from chunks without a single byte buffer',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'im-outbox-stream-store-',
      );
      final store = ImOutboxFileStore(
        keyLoader: (_) async => List<int>.generate(32, (index) => index + 1),
        directoryLoader: () async => directory,
      );
      final chunks = List<Uint8List>.generate(
        12,
        (chunk) => Uint8List.fromList(
          List<int>.generate(8192, (index) => (chunk + index) % 256),
        ),
      );
      final clear = Uint8List.fromList(
        chunks.expand((chunk) => chunk).toList(),
      );

      try {
        final stored = await store.writeStream(
          accountId: 'account-stream',
          clientMessageId: 'client-stream',
          role: 'file',
          fileName: 'large.bin',
          contentType: 'application/octet-stream',
          clearLength: clear.length,
          source: Stream<List<int>>.fromIterable(chunks),
        );

        expect(stored.length, clear.length);
        expect(
          await store.readBytes(
            accountId: 'account-stream',
            clientMessageId: 'client-stream',
            file: stored,
          ),
          clear,
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('stream copy rejects files that change after selection', () async {
    final directory = await Directory.systemTemp.createTemp(
      'im-outbox-stream-mismatch-',
    );
    final store = ImOutboxFileStore(
      keyLoader: (_) async => List<int>.filled(32, 7),
      directoryLoader: () async => directory,
    );

    try {
      await expectLater(
        store.writeStream(
          accountId: 'account-stream',
          clientMessageId: 'client-mismatch',
          role: 'file',
          fileName: 'changed.bin',
          contentType: 'application/octet-stream',
          clearLength: 5,
          source: Stream<List<int>>.value(const [1, 2, 3]),
        ),
        throwsStateError,
      );
      final queued = await directory
          .list(recursive: true)
          .where((entity) => entity is File && entity.path.endsWith('.imq'))
          .toList();
      expect(queued, isEmpty);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}

bool _contains(List<int> haystack, List<int> needle) {
  if (needle.isEmpty || needle.length > haystack.length) return false;
  for (var start = 0; start <= haystack.length - needle.length; start += 1) {
    var matches = true;
    for (var offset = 0; offset < needle.length; offset += 1) {
      if (haystack[start + offset] != needle[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}
