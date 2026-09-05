import 'dart:typed_data';

enum AttachmentPreviewStatus { ready, unsupported, pending }

final class AttachmentPreviewSession {
  const AttachmentPreviewSession({
    required this.sessionId,
    required this.status,
    required this.previewKind,
    required this.contentType,
    required this.previewUrl,
    required this.expiresAt,
    required this.renewAfterSeconds,
    required this.originalDownloadAllowed,
    required this.originalDownloadUrl,
  });

  final String sessionId;
  final AttachmentPreviewStatus status;
  final String previewKind;
  final String contentType;

  /// Short-lived, device-bound relative URL. Keep in memory only.
  final String previewUrl;
  final DateTime? expiresAt;
  final int renewAfterSeconds;
  final bool originalDownloadAllowed;

  /// Authenticated original-download path. This is never a preview ticket.
  final String originalDownloadUrl;

  bool get ready => status == AttachmentPreviewStatus.ready;
}

final class AttachmentContentRange {
  const AttachmentContentRange({
    required this.start,
    required this.end,
    required this.totalLength,
  });

  final int start;
  final int end;
  final int totalLength;

  int get length => end - start + 1;
}

final class AttachmentPreviewChunk {
  const AttachmentPreviewChunk({
    required this.bytes,
    required this.range,
    required this.completeResponse,
  });

  final Uint8List bytes;
  final AttachmentContentRange range;
  final bool completeResponse;
}

sealed class AttachmentPreviewException implements Exception {
  const AttachmentPreviewException(this.message);

  final String message;

  @override
  String toString() => message;
}

final class AttachmentPreviewProtocolException
    extends AttachmentPreviewException {
  const AttachmentPreviewProtocolException(super.message, {this.statusCode});

  final int? statusCode;
}

final class AttachmentPreviewSessionExpired extends AttachmentPreviewException {
  const AttachmentPreviewSessionExpired(this.statusCode) : super('附件预览会话已失效');

  final int statusCode;
}

final class AttachmentRangeNotSatisfiable extends AttachmentPreviewException {
  const AttachmentRangeNotSatisfiable({required this.totalLength})
    : super('附件分片范围无效');

  final int? totalLength;
}

final class AttachmentPreviewCancelled extends AttachmentPreviewException {
  const AttachmentPreviewCancelled() : super('附件预览已取消');
}

final class AttachmentPreviewFile {
  const AttachmentPreviewFile({required this.path, required this.resumedBytes});

  final String path;
  final int resumedBytes;
}
