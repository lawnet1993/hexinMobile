import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/auth/application/auth_controller.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';

MobileSession session({
  String user = 'a',
  String im = 'https://im.test',
  String oa = 'https://oa.test',
  String token = 'fixture',
}) => MobileSession(
  accessToken: token,
  deviceId: 'device',
  userId: user,
  displayName: 'Fixture',
  username: 'fixture',
  policySignatureKey: '',
  imApiUrl: im,
  oaApiUrl: oa,
);

class _Auth extends AuthController {
  @override
  Future<MobileSession?> build() async => session();
  void replace(MobileSession? value) => state = AsyncData(value);
}

const videoKey = (
  attachmentId: 'video',
  fileName: 'fixture.mp4',
  coverObjectId: 'cover',
  coverSha256: 'cover-digest',
  size: 100,
);

void main() {
  test(
    'media namespace separates accounts and both service endpoints, not tokens',
    () {
      final original = imMediaCacheNamespace(session());
      expect(imMediaCacheNamespace(session(token: 'rotated')), original);
      expect(imMediaCacheNamespace(session(user: 'b')), isNot(original));
      expect(
        imMediaCacheNamespace(session(im: 'https://other.test')),
        isNot(original),
      );
      expect(
        imMediaCacheNamespace(session(oa: 'https://other.test')),
        isNot(original),
      );
      expect(original, matches(RegExp(r'^[0-9a-f]{64}$')));
    },
  );

  test(
    'token refresh retains memory; endpoint change and logout clear it',
    () async {
      final container = ProviderContainer.test(
        overrides: [authControllerProvider.overrideWith(_Auth.new)],
      );
      addTearDown(container.dispose);
      await container.read(authControllerProvider.future);
      final subscription = container.listen(
        imBinaryMemoryCacheProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      final cache = container.read(imBinaryMemoryCacheProvider);
      cache.write('a', 'image', Uint8List.fromList([1]));
      final auth = container.read(authControllerProvider.notifier) as _Auth;
      auth.replace(session(token: 'rotated'));
      await container.pump();
      expect(container.read(imBinaryMemoryCacheProvider), same(cache));
      expect(cache.entryCount, 1);
      auth.replace(session(im: 'https://other.test'));
      await container.pump();
      final next = container.read(imBinaryMemoryCacheProvider);
      expect(next, isNot(same(cache)));
      expect(cache.entryCount, 0);
      next.write('a', 'image', Uint8List.fromList([2]));
      auth.replace(null);
      await container.pump();
      expect(next.entryCount, 0);
    },
  );

  for (final kind in ['image', 'media', 'oa']) {
    test(
      '$kind rejects late bytes even before auth state publishes a change',
      () async {
        var account = 'a';
        final entered = Completer<void>();
        final release = Completer<void>();
        final cache = ImBinaryMemoryCache();
        final bytes = Uint8List.fromList([1]);
        Future<Uint8List> download() async {
          entered.complete();
          await release.future;
          return bytes;
        }

        var diskWrites = 0;
        final container = ProviderContainer.test(
          overrides: [
            imMediaCacheAccountLoaderProvider.overrideWithValue(
              () async => account,
            ),
            imBinaryMemoryCacheProvider.overrideWithValue(cache),
            imMessageImageDiskCacheReaderProvider.overrideWithValue(
              ({
                required accountId,
                required imageId,
                required sha256Value,
              }) async => null,
            ),
            imMessageImageDiskCacheWriterProvider.overrideWithValue(({
              required accountId,
              required imageId,
              required sha256Value,
              required bytes,
            }) async {
              diskWrites++;
            }),
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
          'media' => imMediaAttachmentProvider((
            attachmentId: 'a',
            cover: true,
          )),
          _ => oaAttachmentThumbnailProvider('a'),
        };
        final subscription = container.listen(provider, (_, _) {});
        addTearDown(subscription.close);
        final result = expectLater(
          container.read(provider.future),
          throwsA(isA<SessionChangedException>()),
        );
        await entered.future;
        account = 'b';
        final currentBytes = Uint8List.fromList([2]);
        cache.write('b', 'current', currentBytes);
        release.complete();
        await result;
        expect(cache.read('b', 'current'), same(currentBytes));
        expect(diskWrites, 0);
      },
    );
  }

  test('video preview disk keys isolate two accounts with identical attachment ids', () async {
    final files = <String, String>{};
    var downloads = 0;
    Future<String?> open(String account) async {
      final container = ProviderContainer.test(
        overrides: [
          imMediaCacheAccountLoaderProvider.overrideWithValue(
            () async => account,
          ),
          imVideoPreviewCacheReaderProvider.overrideWithValue(
            (key) async => files[key],
          ),
          imVideoPreviewCacheWriterProvider.overrideWithValue((
            key,
            bytes,
          ) async {
            return files[key] = '/fixture/$account.jpg';
          }),
          imMediaAttachmentBytesLoaderProvider.overrideWithValue((
            _, {
            required cover,
          }) async {
            downloads++;
            return Uint8List.fromList([downloads]);
          }),
        ],
      );
      try {
        return (await container.read(imVideoPreviewProvider(videoKey).future))
            ?.filePath;
      } finally {
        container.dispose();
      }
    }

    expect(await open('a'), '/fixture/a.jpg');
    expect(await open('b'), '/fixture/b.jpg');
    expect(await open('a'), '/fixture/a.jpg');
    expect(downloads, 2);
    expect(
      files.keys,
      unorderedEquals([
        'a:cover:cover:cover-digest',
        'b:cover:cover:cover-digest',
      ]),
    );
  });

  test(
    'video without a cover never downloads the original for a thumbnail',
    () async {
      var downloads = 0;
      final container = ProviderContainer.test(
        overrides: [
          imMediaCacheAccountLoaderProvider.overrideWithValue(() async => 'a'),
          imVideoPreviewCacheReaderProvider.overrideWithValue(
            (_) async => null,
          ),
          imMediaAttachmentBytesLoaderProvider.overrideWithValue((
            _, {
            required cover,
          }) async {
            downloads++;
            return Uint8List.fromList([1]);
          }),
        ],
      );
      addTearDown(container.dispose);
      final source = await container.read(
        imVideoPreviewProvider((
          attachmentId: 'video-without-cover',
          fileName: 'fixture.mp4',
          coverObjectId: '',
          coverSha256: '',
          size: 8 * 1024 * 1024,
        )).future,
      );
      expect(source, isNull);
      expect(downloads, 0);
    },
  );

  for (final phase in ['disk', 'cover', 'cover-error', 'write']) {
    test(
      'video $phase boundary rejects a changed secure-store identity',
      () async {
        var account = 'a';
        final entered = Completer<void>();
        final release = Completer<void>();
        final writes = <String>[];
        final requests = <bool>[];
        Future<void> gate(String current) async {
          if (phase != current) return;
          entered.complete();
          await release.future;
        }

        final container = ProviderContainer.test(
          overrides: [
            imMediaCacheAccountLoaderProvider.overrideWithValue(
              () async => account,
            ),
            imVideoPreviewCacheReaderProvider.overrideWithValue((key) async {
              await gate('disk');
              return phase == 'disk' ? '/fixture/a.jpg' : null;
            }),
            imVideoPreviewCacheWriterProvider.overrideWithValue((
              key,
              bytes,
            ) async {
              writes.add(key);
              await gate('write');
              return '/fixture/a.jpg';
            }),
            imMediaAttachmentBytesLoaderProvider.overrideWithValue((
              _, {
              required cover,
            }) async {
              requests.add(cover);
              if (cover) {
                await gate('cover');
                await gate('cover-error');
                if (phase == 'cover-error') {
                  throw StateError('fixture network failure');
                }
              }
              return Uint8List.fromList([1]);
            }),
          ],
        );
        addTearDown(() {
          if (!release.isCompleted) release.complete();
          container.dispose();
        });
        final listener = container.listen(
          imVideoPreviewProvider(videoKey),
          (_, _) {},
        );
        addTearDown(listener.close);
        final result = expectLater(
          container.read(imVideoPreviewProvider(videoKey).future),
          throwsA(isA<SessionChangedException>()),
        );
        await entered.future;
        account = 'b';
        release.complete();
        await result;
        expect(
          writes,
          phase == 'write' ? ['a:cover:cover:cover-digest'] : isEmpty,
        );
        if (phase == 'disk') expect(requests, isEmpty);
        if (phase == 'cover-error') expect(requests, [true]);
      },
    );
  }
}
