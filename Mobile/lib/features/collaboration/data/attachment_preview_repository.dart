import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/collaboration_client.dart';
import '../../../core/storage/secure_session_store.dart';
import '../domain/attachment_preview.dart';

const attachmentPreviewChunkBytes = 4 * 1024 * 1024;

final attachmentPreviewRepositoryProvider =
    Provider<AttachmentPreviewRepository>((ref) {
      return AttachmentPreviewRepository(
        ref.read(collaborationClientProvider),
        ref.read(secureSessionStoreProvider),
      );
    });

abstract interface class AttachmentPreviewGateway {
  Future<AttachmentPreviewSession> createImMediaSession(
    String attachmentId, {
    bool cover = false,
    CancelToken? cancelToken,
    MobileSession? expectedSession,
  });

  Future<AttachmentPreviewChunk> readSingleRange({
    required AttachmentPreviewSession session,
    required int start,
    required int expectedTotalLength,
    int length = attachmentPreviewChunkBytes,
    CancelToken? cancelToken,
    MobileSession? expectedSession,
  });

  Future<AttachmentPreviewSession> renewImSession(
    AttachmentPreviewSession session, {
    CancelToken? cancelToken,
    MobileSession? expectedSession,
  });

  Future<void> closeImSession(
    AttachmentPreviewSession session, {
    CancelToken? cancelToken,
    MobileSession? expectedSession,
  });
}

final class AttachmentPreviewRepository implements AttachmentPreviewGateway {
  AttachmentPreviewRepository(this._client, this._sessionStore);

  final CollaborationClient _client;
  final SecureSessionStore _sessionStore;

  @override
  Future<AttachmentPreviewSession> createImMediaSession(
    String attachmentId, {
    bool cover = false,
    CancelToken? cancelToken,
    MobileSession? expectedSession,
  }) async {
    final normalizedId = attachmentId.trim();
    if (normalizedId.isEmpty) {
      throw const AttachmentPreviewProtocolException('媒体附件无效');
    }
    final session = expectedSession ?? await _requireSession();
    await _ensureCurrent(session);
    final dio = await _client.forIm(forSession: session);
    try {
      final response = await dio.post<Map<String, Object?>>(
        '/api/im/media-attachments/${Uri.encodeComponent(normalizedId)}/preview-sessions',
        queryParameters: cover ? const {'cover': true} : null,
        cancelToken: cancelToken,
        options: Options(
          contentType: Headers.jsonContentType,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      await _ensureCurrent(session);
      if (response.statusCode == 404 || response.statusCode == 410) {
        throw AttachmentPreviewSessionExpired(response.statusCode!);
      }
      if (response.statusCode != 200) {
        throw AttachmentPreviewProtocolException(
          '附件预览会话创建失败',
          statusCode: response.statusCode,
        );
      }
      return _parseSession(response.data ?? const <String, Object?>{});
    } finally {
      dio.close(force: true);
    }
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
    if (!session.ready || session.previewUrl.isEmpty) {
      throw const AttachmentPreviewProtocolException('附件预览尚未就绪');
    }
    if (start < 0 || expectedTotalLength <= 0) {
      throw const AttachmentPreviewProtocolException('附件分片参数无效');
    }
    if (length <= 0 || length > attachmentPreviewChunkBytes) {
      throw const AttachmentPreviewProtocolException('附件分片不得超过 4 MiB');
    }
    final activeSession = expectedSession ?? await _requireSession();
    await _ensureCurrent(activeSession);
    final end = start + length - 1;
    final dio = await _client.forIm(forSession: activeSession);
    try {
      final response = await dio.get<List<int>>(
        session.previewUrl,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.bytes,
          headers: {'Range': 'bytes=$start-$end'},
          validateStatus: (status) =>
              status != null &&
              (status < 300 ||
                  status == 404 ||
                  status == 410 ||
                  status == 416 ||
                  status >= 500),
        ),
      );
      await _ensureCurrent(activeSession);
      final status = response.statusCode;
      if (status == 404 || status == 410) {
        throw AttachmentPreviewSessionExpired(status!);
      }
      if (status == 416) {
        throw AttachmentRangeNotSatisfiable(
          totalLength: _parseUnsatisfiedTotal(
            response.headers.value('content-range'),
          ),
        );
      }
      final bytes = Uint8List.fromList(response.data ?? const <int>[]);
      if (status == 206) {
        final range = _parseContentRange(
          response.headers.value('content-range'),
        );
        if (range == null ||
            range.start != start ||
            range.end > end ||
            range.totalLength != expectedTotalLength ||
            range.length != bytes.length) {
          throw AttachmentPreviewProtocolException(
            '附件分片响应范围不一致',
            statusCode: status,
          );
        }
        return AttachmentPreviewChunk(
          bytes: bytes,
          range: range,
          completeResponse: false,
        );
      }
      if (status == 200) {
        if (start != 0 || bytes.length != expectedTotalLength) {
          throw AttachmentPreviewProtocolException(
            '附件完整响应长度不一致',
            statusCode: status,
          );
        }
        return AttachmentPreviewChunk(
          bytes: bytes,
          range: AttachmentContentRange(
            start: 0,
            end: bytes.length - 1,
            totalLength: bytes.length,
          ),
          completeResponse: true,
        );
      }
      throw AttachmentPreviewProtocolException('附件分片读取失败', statusCode: status);
    } finally {
      dio.close(force: true);
    }
  }

  @override
  Future<AttachmentPreviewSession> renewImSession(
    AttachmentPreviewSession session, {
    CancelToken? cancelToken,
    MobileSession? expectedSession,
  }) async {
    if (session.sessionId.isEmpty) {
      throw const AttachmentPreviewProtocolException('附件预览会话无效');
    }
    final activeSession = expectedSession ?? await _requireSession();
    await _ensureCurrent(activeSession);
    final dio = await _client.forIm(forSession: activeSession);
    try {
      final response = await dio.post<Map<String, Object?>>(
        '/api/im/attachment-preview-sessions/${Uri.encodeComponent(session.sessionId)}/renew',
        cancelToken: cancelToken,
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      await _ensureCurrent(activeSession);
      if (response.statusCode == 404 || response.statusCode == 410) {
        throw AttachmentPreviewSessionExpired(response.statusCode!);
      }
      if (response.statusCode != 200) {
        throw AttachmentPreviewProtocolException(
          '附件预览会话续期失败',
          statusCode: response.statusCode,
        );
      }
      final data = response.data ?? const <String, Object?>{};
      return AttachmentPreviewSession(
        sessionId: _text(data['sessionId']).isEmpty
            ? session.sessionId
            : _text(data['sessionId']),
        status: session.status,
        previewKind: session.previewKind,
        contentType: session.contentType,
        previewUrl: session.previewUrl,
        expiresAt: _date(data['expiresAt']) ?? session.expiresAt,
        renewAfterSeconds:
            _integer(data['renewAfterSeconds']) ?? session.renewAfterSeconds,
        originalDownloadAllowed: session.originalDownloadAllowed,
        originalDownloadUrl: session.originalDownloadUrl,
      );
    } finally {
      dio.close(force: true);
    }
  }

  @override
  Future<void> closeImSession(
    AttachmentPreviewSession session, {
    CancelToken? cancelToken,
    MobileSession? expectedSession,
  }) async {
    if (session.sessionId.isEmpty) return;
    final activeSession = expectedSession ?? await _requireSession();
    await _ensureCurrent(activeSession);
    final dio = await _client.forIm(forSession: activeSession);
    try {
      final response = await dio.delete<void>(
        '/api/im/attachment-preview-sessions/${Uri.encodeComponent(session.sessionId)}',
        cancelToken: cancelToken,
        options: Options(
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      await _ensureCurrent(activeSession);
      if (response.statusCode != 204 && response.statusCode != 404) {
        throw AttachmentPreviewProtocolException(
          '附件预览会话关闭失败',
          statusCode: response.statusCode,
        );
      }
    } finally {
      dio.close(force: true);
    }
  }

  AttachmentPreviewSession _parseSession(Map<String, Object?> data) {
    final rawStatus = _text(data['status']).toLowerCase();
    final status = switch (rawStatus) {
      'ready' => AttachmentPreviewStatus.ready,
      'unsupported' => AttachmentPreviewStatus.unsupported,
      'pending' => AttachmentPreviewStatus.pending,
      _ => throw const AttachmentPreviewProtocolException('附件预览状态无效'),
    };
    final sessionId = _text(data['sessionId']);
    final previewUrl = _text(data['previewUrl']);
    if (status == AttachmentPreviewStatus.ready &&
        (sessionId.isEmpty || !_validPreviewUrl(previewUrl, sessionId))) {
      throw const AttachmentPreviewProtocolException('附件预览地址无效');
    }
    return AttachmentPreviewSession(
      sessionId: sessionId,
      status: status,
      previewKind: _text(data['previewKind']),
      contentType: _text(data['contentType']),
      previewUrl: previewUrl,
      expiresAt: _date(data['expiresAt']),
      renewAfterSeconds: _integer(data['renewAfterSeconds']) ?? 0,
      originalDownloadAllowed: data['originalDownloadAllowed'] == true,
      originalDownloadUrl: _validOriginalPath(
        _text(data['originalDownloadUrl']),
      ),
    );
  }

  bool _validPreviewUrl(String value, String sessionId) {
    final uri = Uri.tryParse(value);
    return uri != null &&
        !uri.hasScheme &&
        !uri.hasAuthority &&
        uri.path == '/api/im/attachment-preview-sessions/$sessionId/content' &&
        (uri.queryParameters['ticket']?.isNotEmpty ?? false);
  }

  String _validOriginalPath(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.hasScheme ||
        uri.hasAuthority ||
        !uri.path.startsWith('/api/im/')) {
      return '';
    }
    return value;
  }

  Future<MobileSession> _requireSession() async {
    final session = await _sessionStore.readSession();
    if (session == null) throw StateError('登录状态已失效，请重新登录');
    return session;
  }

  Future<void> _ensureCurrent(MobileSession expected) =>
      _sessionStore.withCurrentSession(expected, () async {});
}

AttachmentContentRange? _parseContentRange(String? value) {
  final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(value ?? '');
  if (match == null) return null;
  final start = int.tryParse(match.group(1)!);
  final end = int.tryParse(match.group(2)!);
  final total = int.tryParse(match.group(3)!);
  if (start == null ||
      end == null ||
      total == null ||
      start < 0 ||
      end < start ||
      total <= end) {
    return null;
  }
  return AttachmentContentRange(start: start, end: end, totalLength: total);
}

int? _parseUnsatisfiedTotal(String? value) {
  final match = RegExp(r'^bytes \*/(\d+)$').firstMatch(value ?? '');
  return match == null ? null : int.tryParse(match.group(1)!);
}

String _text(Object? value) => value?.toString().trim() ?? '';

int? _integer(Object? value) =>
    value is num ? value.toInt() : int.tryParse(_text(value));

DateTime? _date(Object? value) => DateTime.tryParse(_text(value));
