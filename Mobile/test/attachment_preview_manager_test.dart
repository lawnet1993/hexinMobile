import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/application/attachment_preview_manager.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/attachment_preview_repository.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/attachment_preview.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'complete chunks survive interruption and resume from the part length',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'preview-manager-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = await _sessionStore();
      final bytes = Uint8List.fromList(
        List<int>.generate(
          attachmentPreviewChunkBytes + 3,
          (index) => index % 251,
        ),
      );
      final digest = sha256.convert(bytes).toString();
      final interruptedGateway = _FakeGateway(bytes, failAfterChunks: 1);
      final interrupted = AttachmentPreviewManager(
        interruptedGateway,
        store,
        directoryLoader: () async => directory,
      );
      addTearDown(interrupted.dispose);

      await expectLater(
        interrupted.prepareImMedia(
          attachmentId: 'media-1',
          fileName: 'fixture.mp4',
          expectedSize: bytes.length,
          expectedSha256: digest,
        ),
        throwsA(isA<AttachmentPreviewCancelled>()),
      );
      final parts = directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.part'))
          .toList();
      expect(parts, hasLength(1));
      expect(await parts.single.length(), attachmentPreviewChunkBytes);

      final resumedGateway = _FakeGateway(bytes);
      final resumed = AttachmentPreviewManager(
        resumedGateway,
        store,
        directoryLoader: () async => directory,
      );
      addTearDown(resumed.dispose);
      final result = await resumed.prepareImMedia(
        attachmentId: 'media-1',
        fileName: 'fixture.mp4',
        expectedSize: bytes.length,
        expectedSha256: digest,
      );
      expect(result.resumedBytes, attachmentPreviewChunkBytes);
      expect(resumedGateway.starts, [attachmentPreviewChunkBytes]);
      final completed = File(result.path);
      expect(await completed.length(), bytes.length);
      expect(
        await sha256.bind(completed.openRead()).first,
        sha256.convert(bytes),
      );
      expect(
        directory.listSync().whereType<File>().where(
          (file) => file.path.endsWith('.part'),
        ),
        isEmpty,
      );
    },
  );

  test(
    'an expired session is rebuilt once without discarding the offset',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'preview-rebuild-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = await _sessionStore();
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final gateway = _FakeGateway(bytes, expireOnce: true);
      final manager = AttachmentPreviewManager(
        gateway,
        store,
        directoryLoader: () async => directory,
      );
      addTearDown(manager.dispose);

      final result = await manager.prepareImMedia(
        attachmentId: 'media-2',
        fileName: 'fixture.mp4',
        expectedSize: bytes.length,
        expectedSha256: sha256.convert(bytes).toString(),
      );
      expect(await File(result.path).readAsBytes(), bytes);
      expect(gateway.createCount, 2);
      expect(gateway.starts, [0, 0]);
    },
  );

  test(
    'digest mismatch deletes the partial file instead of publishing it',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'preview-digest-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final store = await _sessionStore();
      final gateway = _FakeGateway(Uint8List.fromList([1, 2, 3, 4]));
      final manager = AttachmentPreviewManager(
        gateway,
        store,
        directoryLoader: () async => directory,
      );
      addTearDown(manager.dispose);

      await expectLater(
        manager.prepareImMedia(
          attachmentId: 'media-3',
          fileName: 'fixture.mp4',
          expectedSize: 4,
          expectedSha256: List.filled(64, '0').join(),
        ),
        throwsA(isA<AttachmentPreviewProtocolException>()),
      );
      expect(directory.listSync().whereType<File>(), isEmpty);
    },
  );

  test('the same attachment is cached under different account paths', () async {
    final directory = await Directory.systemTemp.createTemp('preview-scope-');
    addTearDown(() => directory.delete(recursive: true));
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    final digest = sha256.convert(bytes).toString();
    final first = AttachmentPreviewManager(
      _FakeGateway(bytes),
      await _sessionStore(userId: 'member-a'),
      directoryLoader: () async => directory,
    );
    final second = AttachmentPreviewManager(
      _FakeGateway(bytes),
      await _sessionStore(userId: 'member-b'),
      directoryLoader: () async => directory,
    );
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    final firstFile = await first.prepareImMedia(
      attachmentId: 'shared-media',
      fileName: 'fixture.mp4',
      expectedSize: bytes.length,
      expectedSha256: digest,
    );
    final secondFile = await second.prepareImMedia(
      attachmentId: 'shared-media',
      fileName: 'fixture.mp4',
      expectedSize: bytes.length,
      expectedSha256: digest,
    );
    expect(firstFile.path, isNot(secondFile.path));
    expect(directory.listSync().whereType<File>(), hasLength(2));
  });
}

Future<SecureSessionStore> _sessionStore({String userId = 'member-1'}) async {
  FlutterSecureStorage.setMockInitialValues({});
  final store = SecureSessionStore();
  await store.saveSession(
    MobileSession(
      accessToken: 'token',
      deviceId: 'mobile-device',
      installationId: 'mobile-installation',
      userId: userId,
      displayName: 'Fixture',
      username: 'fixture',
      policySignatureKey: '',
      imApiUrl: 'https://im.test',
      oaApiUrl: '',
    ),
  );
  return store;
}

final class _FakeGateway implements AttachmentPreviewGateway {
  _FakeGateway(this.bytes, {this.failAfterChunks, this.expireOnce = false});

  final Uint8List bytes;
  final int? failAfterChunks;
  final bool expireOnce;
  final List<int> starts = [];
  int createCount = 0;
  int closeCount = 0;
  int successfulChunks = 0;
  bool expired = false;

  @override
  Future<AttachmentPreviewSession> createImMediaSession(
    String attachmentId, {
    bool cover = false,
    CancelToken? cancelToken,
    MobileSession? expectedSession,
  }) async {
    createCount++;
    return AttachmentPreviewSession(
      sessionId: 'session-$createCount',
      status: AttachmentPreviewStatus.ready,
      previewKind: cover ? 'image' : 'video',
      contentType: cover ? 'image/jpeg' : 'video/mp4',
      previewUrl:
          '/api/im/attachment-preview-sessions/session-$createCount/content?ticket=opaque',
      expiresAt: null,
      renewAfterSeconds: 120,
      originalDownloadAllowed: false,
      originalDownloadUrl: '',
    );
  }

  @override
  Future<AttachmentPreviewChunk> readSingleRange({
    required AttachmentPreviewSession session,
    required int start,
    required int expectedTotalLength,
    int length = attachmentPreviewChunkBytes,
    CancelToken? cancelToken,
    MobileSession? expectedSession,
  }) async {
    starts.add(start);
    if (cancelToken?.isCancelled == true) {
      throw const AttachmentPreviewCancelled();
    }
    if (expireOnce && !expired) {
      expired = true;
      throw const AttachmentPreviewSessionExpired(410);
    }
    if (failAfterChunks != null && successfulChunks >= failAfterChunks!) {
      throw const AttachmentPreviewCancelled();
    }
    final end = min(start + length, bytes.length);
    final chunk = Uint8List.fromList(bytes.sublist(start, end));
    successfulChunks++;
    return AttachmentPreviewChunk(
      bytes: chunk,
      range: AttachmentContentRange(
        start: start,
        end: end - 1,
        totalLength: bytes.length,
      ),
      completeResponse: false,
    );
  }

  @override
  Future<AttachmentPreviewSession> renewImSession(
    AttachmentPreviewSession session, {
    CancelToken? cancelToken,
    MobileSession? expectedSession,
  }) async => session;

  @override
  Future<void> closeImSession(
    AttachmentPreviewSession session, {
    CancelToken? cancelToken,
    MobileSession? expectedSession,
  }) async {
    closeCount++;
  }
}
