import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';

final _scope = NotifierProvider<_Scope, String>(_Scope.new);

class _Scope extends Notifier<String> {
  @override
  String build() => 'account-a';
  void change() => state = 'account-b';
}

void main() {
  for (final kind in ['image', 'media', 'oa']) {
    test('$kind late account A bytes cannot evict account B cache', () async {
      final cache = ImBinaryMemoryCache();
      final entered = Completer<void>();
      final release = Completer<void>();
      final oldBytes = Uint8List.fromList([1]);
      final newBytes = Uint8List.fromList([2]);
      late ProviderContainer container;
      Future<Uint8List> download() async {
        final account = container.read(_scope);
        if (account == 'account-a') {
          if (!entered.isCompleted) entered.complete();
          await release.future;
          return oldBytes;
        }
        return newBytes;
      }

      container = ProviderContainer.test(
        overrides: [
          collaborationAccountScopeProvider.overrideWith(
            (ref) => ref.watch(_scope),
          ),
          imBinaryMemoryCacheProvider.overrideWithValue(cache),
          imMediaCacheAccountLoaderProvider.overrideWithValue(
            () async => container.read(_scope),
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
          imMessageImageBytesLoaderProvider.overrideWithValue(
            (_, _) => download(),
          ),
          imMediaAttachmentBytesLoaderProvider.overrideWithValue(
            (_, {required cover}) => download(),
          ),
          oaAttachmentThumbnailBytesLoaderProvider.overrideWithValue(
            (_) => download(),
          ),
        ],
      );
      addTearDown(() {
        if (!release.isCompleted) release.complete();
        container.dispose();
      });
      final provider = switch (kind) {
        'image' => imMessageImageProvider((
          messageId: 'm',
          imageId: 'i',
          sha256: '',
        )),
        'media' => imMediaAttachmentProvider((attachmentId: 'a', cover: true)),
        _ => oaAttachmentThumbnailProvider('a'),
      };
      final listener = container.listen(provider, (_, _) {});
      addTearDown(listener.close);
      await entered.future;
      container.read(_scope.notifier).change();
      await container.pump();
      expect(await container.read(provider.future), same(newBytes));
      release.complete();
      await Future<void>.delayed(Duration.zero);
      await container.pump();
      final key = switch (kind) {
        'image' => 'image:m:i',
        'media' => 'media:a:1',
        _ => 'oa-thumbnail:a',
      };
      expect(cache.read('account-b', key), same(newBytes));
    });
  }

  test(
    'image digest change does not reuse the previous version in memory',
    () async {
      var downloads = 0;
      final container = ProviderContainer.test(
        overrides: [
          imMediaCacheAccountLoaderProvider.overrideWithValue(
            () async => 'account',
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
          imMessageImageBytesLoaderProvider.overrideWithValue(
            (_, _) async => Uint8List.fromList([++downloads]),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(
        await container.read(
          imMessageImageProvider((
            messageId: 'm',
            imageId: 'i',
            sha256: 'version-one',
          )).future,
        ),
        [1],
      );
      expect(
        await container.read(
          imMessageImageProvider((
            messageId: 'm',
            imageId: 'i',
            sha256: 'version-two',
          )).future,
        ),
        [2],
      );
      expect(downloads, 2);
    },
  );
}
