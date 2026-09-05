import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_message_image_cache.dart';

void main() {
  test('binary cache enforces byte and entry limits with LRU eviction', () {
    final cache = ImBinaryMemoryCache(maxEntries: 2, maxBytes: 6);
    final first = Uint8List.fromList([1, 1, 1]);
    final second = Uint8List.fromList([2, 2, 2]);
    final third = Uint8List.fromList([3, 3]);

    cache.write('account-a', 'first', first);
    cache.write('account-a', 'second', second);
    expect(cache.read('account-a', 'first'), same(first));
    cache.write('account-a', 'third', third);

    expect(cache.read('account-a', 'second'), isNull);
    expect(cache.read('account-a', 'first'), same(first));
    expect(cache.read('account-a', 'third'), same(third));
    expect(cache.entryCount, 2);
    expect(cache.totalBytes, 5);
  });

  test('binary cache clears when the signed-in account changes', () {
    final cache = ImBinaryMemoryCache(maxEntries: 4, maxBytes: 16);
    cache.write('account-a', 'image', Uint8List.fromList([1, 2, 3]));

    expect(cache.read('account-b', 'image'), isNull);
    expect(cache.entryCount, 0);
    expect(cache.totalBytes, 0);
  });

  test('image provider reuses bounded cache after auto dispose', () async {
    var downloads = 0;
    final bytes = Uint8List.fromList([9, 8, 7, 6]);
    final container = ProviderContainer.test(
      overrides: [
        imMediaCacheAccountLoaderProvider.overrideWithValue(
          () async => 'account-a',
        ),
        imMessageImageDiskCacheReaderProvider.overrideWithValue(
          ({
            required accountId,
            required imageId,
            required sha256Value,
          }) async => null,
        ),
        imMessageImageDiskCacheWriterProvider.overrideWithValue(
          ({
            required accountId,
            required imageId,
            required sha256Value,
            required bytes,
          }) async {},
        ),
        imMessageImageBytesLoaderProvider.overrideWithValue((
          messageId,
          imageId,
        ) async {
          downloads += 1;
          return bytes;
        }),
      ],
    );
    const key = (messageId: 'message-1', imageId: 'image-1', sha256: '');

    final first = container.listen(
      imMessageImageProvider(key),
      (_, _) {},
      fireImmediately: true,
    );
    expect(
      await container.read(imMessageImageProvider(key).future),
      same(bytes),
    );
    first.close();
    await container.pump();

    final reopened = container.listen(
      imMessageImageProvider(key),
      (_, _) {},
      fireImmediately: true,
    );
    expect(
      await container.read(imMessageImageProvider(key).future),
      same(bytes),
    );
    expect(downloads, 1);

    reopened.close();
    container.dispose();
  });

  test('image provider restores process-cold bytes from disk cache', () async {
    var downloads = 0;
    final bytes = Uint8List.fromList([6, 7, 8, 9]);
    final digest = crypto.sha256.convert(bytes).toString();
    final directory = await Directory.systemTemp.createTemp(
      'hexing-im-disk-cache-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final diskCache = ImMessageImageDiskCache(
      directoryLoader: () async => directory,
    );
    await diskCache.write(
      accountId: 'account-a',
      imageId: 'image-1',
      sha256Value: digest,
      bytes: bytes,
    );
    final container = ProviderContainer.test(
      overrides: [
        imMediaCacheAccountLoaderProvider.overrideWithValue(
          () async => 'account-a',
        ),
        imMessageImageDiskCacheReaderProvider.overrideWithValue(diskCache.read),
        imMessageImageDiskCacheWriterProvider.overrideWithValue(
          diskCache.write,
        ),
        imMessageImageBytesLoaderProvider.overrideWithValue((
          messageId,
          imageId,
        ) async {
          downloads += 1;
          return bytes;
        }),
      ],
    );
    addTearDown(container.dispose);
    final provider = imMessageImageProvider((
      messageId: 'message-1',
      imageId: 'image-1',
      sha256: digest,
    ));
    // Model a mounted image while real filesystem IO spans event-loop turns.
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    final restored = await container.read(provider.future);

    expect(restored, orderedEquals(bytes));
    expect(downloads, 0);
  });

  test(
    'disk image cache isolates accounts and rejects corrupted bytes',
    () async {
      final bytes = Uint8List.fromList([1, 3, 5, 7, 9]);
      final digest = crypto.sha256.convert(bytes).toString();
      final directory = await Directory.systemTemp.createTemp(
        'hexing-im-disk-integrity-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final diskCache = ImMessageImageDiskCache(
        directoryLoader: () async => directory,
      );
      await diskCache.write(
        accountId: 'account-a',
        imageId: 'image-1',
        sha256Value: digest,
        bytes: bytes,
      );

      expect(
        await diskCache.read(
          accountId: 'account-b',
          imageId: 'image-1',
          sha256Value: digest,
        ),
        isNull,
      );
      final cachedFile = directory.listSync().whereType<File>().singleWhere(
        (file) => file.path.endsWith('.bin'),
      );
      await cachedFile.writeAsBytes([0, 0, 0], flush: true);
      expect(
        await diskCache.read(
          accountId: 'account-a',
          imageId: 'image-1',
          sha256Value: digest,
        ),
        isNull,
      );
      expect(await cachedFile.exists(), isFalse);
    },
  );

  test(
    'OA thumbnail shares bounded cache after provider auto dispose',
    () async {
      var downloads = 0;
      final bytes = Uint8List.fromList([5, 4, 3, 2, 1]);
      final container = ProviderContainer.test(
        overrides: [
          imMediaCacheAccountLoaderProvider.overrideWithValue(
            () async => 'account-a',
          ),
          oaAttachmentThumbnailBytesLoaderProvider.overrideWithValue((
            attachmentId,
          ) async {
            downloads += 1;
            return bytes;
          }),
        ],
      );

      final first = container.listen(
        oaAttachmentThumbnailProvider('attachment-1'),
        (_, _) {},
        fireImmediately: true,
      );
      expect(
        await container.read(
          oaAttachmentThumbnailProvider('attachment-1').future,
        ),
        same(bytes),
      );
      first.close();
      await container.pump();

      final reopened = container.listen(
        oaAttachmentThumbnailProvider('attachment-1'),
        (_, _) {},
        fireImmediately: true,
      );
      expect(
        await container.read(
          oaAttachmentThumbnailProvider('attachment-1').future,
        ),
        same(bytes),
      );
      expect(downloads, 1);

      reopened.close();
      container.dispose();
    },
  );
}
