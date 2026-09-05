import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../../core/config/app_environment.dart';
import '../../../core/storage/secure_session_store.dart';
import '../data/attachment_preview_repository.dart';
import '../domain/attachment_preview.dart';

typedef AttachmentPreviewDirectoryLoader = Future<Directory> Function();

final attachmentPreviewManagerProvider = Provider<AttachmentPreviewManager>((
  ref,
) {
  final manager = AttachmentPreviewManager(
    ref.read(attachmentPreviewRepositoryProvider),
    ref.read(secureSessionStoreProvider),
  );
  ref.onDispose(manager.dispose);
  return manager;
});

final class AttachmentPreviewManager {
  AttachmentPreviewManager(
    this._gateway,
    this._sessionStore, {
    AttachmentPreviewDirectoryLoader? directoryLoader,
  }) : _directoryLoader = directoryLoader ?? _defaultDirectory;

  final AttachmentPreviewGateway _gateway;
  final SecureSessionStore _sessionStore;
  final AttachmentPreviewDirectoryLoader _directoryLoader;
  final Map<String, _PreviewOperation> _operations = {};
  final Map<String, int> _generations = {};
  bool _disposed = false;

  Future<AttachmentPreviewFile> prepareImMedia({
    required String attachmentId,
    required String fileName,
    required int expectedSize,
    required String expectedSha256,
    bool cover = false,
  }) async {
    if (_disposed) throw const AttachmentPreviewCancelled();
    final normalizedId = attachmentId.trim();
    final normalizedSha = expectedSha256.trim().toLowerCase();
    if (normalizedId.isEmpty ||
        expectedSize <= 0 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(normalizedSha)) {
      throw const AttachmentPreviewProtocolException('附件完整性信息无效');
    }
    final session = await _requireSession();
    final scope = _scopeKey(session);
    final operationKey = '$scope:$normalizedId:${cover ? 1 : 0}';
    cancel(operationKey);
    final generation = (_generations[operationKey] ?? 0) + 1;
    _generations[operationKey] = generation;
    final operation = _PreviewOperation(generation, CancelToken());
    _operations[operationKey] = operation;
    try {
      return await _prepare(
        operationKey: operationKey,
        operation: operation,
        session: session,
        attachmentId: normalizedId,
        fileName: fileName,
        expectedSize: expectedSize,
        expectedSha256: normalizedSha,
        cover: cover,
      );
    } finally {
      if (_operations[operationKey] == operation) {
        _operations.remove(operationKey);
      }
    }
  }

  void cancel(String operationKey) {
    final operation = _operations.remove(operationKey);
    operation?.token.cancel('attachment-preview-cancelled');
  }

  void cancelAll() {
    final operations = _operations.values.toList();
    _operations.clear();
    for (final operation in operations) {
      operation.token.cancel('attachment-preview-cancelled');
    }
  }

  void dispose() {
    _disposed = true;
    cancelAll();
  }

  Future<AttachmentPreviewFile> _prepare({
    required String operationKey,
    required _PreviewOperation operation,
    required MobileSession session,
    required String attachmentId,
    required String fileName,
    required int expectedSize,
    required String expectedSha256,
    required bool cover,
  }) async {
    final directory = await _directoryLoader();
    await directory.create(recursive: true);
    _checkActive(operationKey, operation);
    final digest = sha256
        .convert(
          utf8.encode(
            '${_scopeKey(session)}|$attachmentId|$expectedSha256|${cover ? 1 : 0}',
          ),
        )
        .toString();
    final extension = _safeExtension(fileName, cover);
    final completed = File(path.join(directory.path, '$digest$extension'));
    final partial = File(path.join(directory.path, '$digest.part'));

    if (await completed.exists()) {
      if (await _isValid(completed, expectedSize, expectedSha256)) {
        await completed.setLastModified(DateTime.now());
        return AttachmentPreviewFile(path: completed.path, resumedBytes: 0);
      }
      await completed.delete();
    }
    var offset = await partial.exists() ? await partial.length() : 0;
    if (offset < 0 || offset > expectedSize) {
      await _deleteIfExists(partial);
      offset = 0;
    }
    final resumedBytes = offset;
    if (offset == expectedSize) {
      if (await _isValid(partial, expectedSize, expectedSha256)) {
        await partial.rename(completed.path);
        return AttachmentPreviewFile(
          path: completed.path,
          resumedBytes: resumedBytes,
        );
      }
      await partial.delete();
      offset = 0;
    }

    AttachmentPreviewSession? previewSession;
    var rebuilds = 0;
    var rangeResets = 0;
    try {
      while (offset < expectedSize) {
        _checkActive(operationKey, operation);
        previewSession ??= await _gateway.createImMediaSession(
          attachmentId,
          cover: cover,
          cancelToken: operation.token,
          expectedSession: session,
        );
        _checkActive(operationKey, operation);
        if (!previewSession.ready) {
          throw const AttachmentPreviewProtocolException('附件预览尚未就绪');
        }
        final requestLength = (expectedSize - offset).clamp(
          1,
          attachmentPreviewChunkBytes,
        );
        AttachmentPreviewChunk chunk;
        try {
          chunk = await _gateway.readSingleRange(
            session: previewSession,
            start: offset,
            expectedTotalLength: expectedSize,
            length: requestLength,
            cancelToken: operation.token,
            expectedSession: session,
          );
        } on AttachmentPreviewSessionExpired {
          if (rebuilds >= 1) rethrow;
          rebuilds += 1;
          previewSession = null;
          continue;
        } on AttachmentRangeNotSatisfiable catch (error) {
          if (error.totalLength == expectedSize &&
              offset == expectedSize &&
              await _isValid(partial, expectedSize, expectedSha256)) {
            break;
          }
          if (rangeResets >= 1) rethrow;
          rangeResets += 1;
          await _deleteIfExists(partial);
          offset = 0;
          previewSession = null;
          continue;
        }
        _checkActive(operationKey, operation);
        if (chunk.bytes.isEmpty) {
          throw const AttachmentPreviewProtocolException('附件分片为空');
        }
        if (chunk.completeResponse) {
          if (offset != 0) {
            throw const AttachmentPreviewProtocolException('完整响应不能追加到已有分片');
          }
          await partial.writeAsBytes(chunk.bytes, flush: true);
        } else {
          final sink = await partial.open(mode: FileMode.append);
          try {
            await sink.writeFrom(chunk.bytes);
            await sink.flush();
          } finally {
            await sink.close();
          }
        }
        offset = await partial.length();
        if (offset > expectedSize) {
          await partial.delete();
          throw const AttachmentPreviewProtocolException('附件分片长度越界');
        }
      }
      _checkActive(operationKey, operation);
      if (!await _isValid(partial, expectedSize, expectedSha256)) {
        await _deleteIfExists(partial);
        throw const AttachmentPreviewProtocolException('附件完整性校验失败');
      }
      await _deleteIfExists(completed);
      await partial.rename(completed.path);
      return AttachmentPreviewFile(
        path: completed.path,
        resumedBytes: resumedBytes,
      );
    } finally {
      if (previewSession != null) {
        try {
          await _gateway.closeImSession(
            previewSession,
            expectedSession: session,
          );
        } catch (_) {
          // Server sessions expire independently. Cleanup failure must not
          // hide the verified file result or the original error.
        }
      }
    }
  }

  void _checkActive(String key, _PreviewOperation operation) {
    if (_disposed ||
        operation.token.isCancelled ||
        _operations[key] != operation ||
        _generations[key] != operation.generation) {
      throw const AttachmentPreviewCancelled();
    }
  }

  Future<bool> _isValid(
    File file,
    int expectedSize,
    String expectedSha256,
  ) async {
    if (!await file.exists() || await file.length() != expectedSize) {
      return false;
    }
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString() == expectedSha256;
  }

  Future<MobileSession> _requireSession() async {
    final session = await _sessionStore.readSession();
    if (session == null) throw StateError('登录状态已失效，请重新登录');
    return session;
  }

  String _scopeKey(MobileSession session) => sha256
      .convert(
        utf8.encode(
          [
            AppEnvironment.storageNamespace,
            session.userId.trim(),
            session.imApiUrl.trim(),
          ].join('|'),
        ),
      )
      .toString();
}

final class _PreviewOperation {
  const _PreviewOperation(this.generation, this.token);

  final int generation;
  final CancelToken token;
}

Future<Directory> _defaultDirectory() async {
  final root = await getApplicationSupportDirectory();
  return Directory(
    path.join(
      root.path,
      AppEnvironment.storageDirectoryName('attachment-previews'),
    ),
  );
}

String _safeExtension(String fileName, bool cover) {
  if (cover) return '.jpg';
  final extension = path.extension(fileName).toLowerCase();
  return RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)
      ? extension
      : '.media';
}

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) await file.delete();
}
