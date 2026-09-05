import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

const imUploadDiagnostics = ImUploadDiagnostics();

/// Explicit, profile/debug-only upload failure evidence. Never emits raw bodies,
/// URLs, names, credentials, device identity, arbitrary codes or header values.
class ImUploadDiagnostics {
  const ImUploadDiagnostics({
    this.enabled = const bool.fromEnvironment('MOBILE_IM_UPLOAD_DIAGNOSTICS'),
    this.write,
  });

  final bool enabled;
  final void Function(String)? write;

  void failure(Object error) {
    if (!enabled || kReleaseMode || error is! DioException) return;
    try {
      _record(error);
    } catch (_) {
      // Diagnostic serialization or output must never alter queue recovery.
    }
  }

  void _record(DioException error) {
    final path = Uri.tryParse(error.requestOptions.path)?.path ?? '';
    final operation = switch (path) {
      '/api/im/upload/video' => 'video_upload',
      '/api/im/upload/audio' => 'audio_upload',
      '/api/im/upload/picture' => 'cover_upload',
      final p
          when RegExp(r'^/api/im/conversations/[^/]+/images$').hasMatch(p) =>
        'image_send',
      final p
          when RegExp(r'^/api/im/conversations/[^/]+/attachments$')
              .hasMatch(p) =>
        'file_send',
      final p
          when RegExp(r'^/api/im/conversations/[^/]+/media-messages$')
              .hasMatch(p) =>
        'media_message',
      _ => null,
    };
    if (operation == null) return;
    final response = error.response;
    final body = response?.data;
    final fields = <String>[];
    final fileBytes = <int>[];
    final request = error.requestOptions.data;
    if (request is FormData) {
      for (final field in request.fields) {
        if (_formFields.contains(field.key)) fields.add(field.key);
      }
      for (final file in request.files) {
        if (_formFields.contains(file.key)) fields.add(file.key);
        fileBytes.add(file.value.length);
      }
    }
    final map = body is Map ? body : const <String, Object?>{};
    final rawCode = map['code'] ?? map['Code'];
    final hints = [
      if (body is String) body,
      for (final key in ['code', 'Code', 'title', 'detail', 'message', 'error'])
        if (map[key] is String) map[key] as String,
    ].where((value) => value.length <= 16384).join('\n');
    final signals = <String>[
      for (final entry in _signals.entries)
        if (entry.value.hasMatch(hints)) entry.key,
    ];
    final record = <String, Object?>{
      'sampledAt': DateTime.now().toUtc().toIso8601String(),
      'operation': operation,
      'httpStatus': response?.statusCode,
      'failureType': error.type.name,
      'requestBody': request is FormData ? 'multipart' : 'other',
      'formFields': fields,
      'fileBytes': fileBytes,
      'responseType': _mediaType(_header(response?.headers, 'content-type')),
      'bodyShape': switch (body) {
        null => 'empty',
        Map() => 'object',
        List() => 'array',
        String() => 'string',
        _ => 'other',
      },
      'errorCode': _codes.contains(rawCode) ? rawCode : null,
      // Signals classify known phrases, not a verified backend root cause.
      'errorSignals': signals,
      'requestId': _correlation(_header(response?.headers, 'x-request-id')),
      'correlationId': _correlation(
        _header(response?.headers, 'x-correlation-id'),
      ),
      'traceparent': _correlation(_header(response?.headers, 'traceparent')),
      'bodyTraceId': _correlation(map['traceId'] ?? map['TraceId']),
    };
    (write ?? debugPrint)('MOBILE_IM_UPLOAD ${jsonEncode(record)}');
  }

  static const _formFields = {
    'file',
    'files',
    'files[]',
    'caption',
    'clientMessageId',
  };
  static const _codes = {
    'internal_error',
    'upload_failed',
    'storage_unavailable',
    'file_too_large',
    'validation_failed',
    'unsupported_media_type',
    'invalid_file',
    'unauthorized',
    'forbidden',
    'session_replaced',
    'NoSuchBucket',
    'AccessDenied',
    'InvalidAccessKeyId',
    'SignatureDoesNotMatch',
  };
  static final _signals = <String, RegExp>{
    'missing_bucket': RegExp(
      r'NoSuchBucket|specified bucket does not exist',
      caseSensitive: false,
    ),
    'storage_credentials_rejected': RegExp(
      r'InvalidAccessKeyId|SignatureDoesNotMatch',
      caseSensitive: false,
    ),
    'access_denied': RegExp(
      r'AccessDenied|Access Denied',
      caseSensitive: false,
    ),
    'disk_full': RegExp(
      r'No space left on device|disk is full',
      caseSensitive: false,
    ),
    'payload_too_large': RegExp(
      r'EntityTooLarge|Request body too large',
      caseSensitive: false,
    ),
    'storage_not_configured': RegExp(
      r'(?:object storage|S3|MinIO).{0,80}(?:not configured|missing configuration)',
      caseSensitive: false,
    ),
  };

  static String _mediaType(String? value) {
    final type = value?.split(';').first.trim().toLowerCase();
    return switch (type) {
      'application/json' || 'application/problem+json' => 'json',
      'text/html' => 'html',
      'text/plain' => 'text',
      _ => 'other',
    };
  }

  static String? _header(Headers? headers, String key) {
    final values = headers?[key];
    return values == null || values.isEmpty ? null : values.first;
  }

  static String? _correlation(Object? value) {
    if (value is! String || value.length > 80) return null;
    return RegExp(
          r'^(?:[a-fA-F0-9]{32}|[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}|[a-fA-F0-9]{2}-[a-fA-F0-9]{32}-[a-fA-F0-9]{16}-[a-fA-F0-9]{2}|0[A-Z0-9]{12}:[A-F0-9]{8})$',
        ).hasMatch(value)
        ? value
        : null;
  }
}
