import 'dart:convert';

String mobileFileContentType(String? extension) {
  final normalized = extension?.trim().toLowerCase().replaceFirst('.', '');
  return switch (normalized) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'heic' || 'heif' => 'image/heic',
    'bmp' => 'image/bmp',
    'svg' => 'image/svg+xml',
    'mp4' || 'm4v' => 'video/mp4',
    'webm' => 'video/webm',
    'mov' => 'video/quicktime',
    'mkv' => 'video/x-matroska',
    'mp3' => 'audio/mpeg',
    'm4a' => 'audio/mp4',
    'wav' => 'audio/wav',
    'ogg' || 'oga' => 'audio/ogg',
    'flac' => 'audio/flac',
    'pdf' => 'application/pdf',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt' => 'application/vnd.ms-powerpoint',
    'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    'csv' => 'text/csv',
    'rtf' => 'application/rtf',
    'txt' => 'text/plain',
    'json' => 'application/json',
    'xml' => 'application/xml',
    'zip' => 'application/zip',
    'rar' => 'application/vnd.rar',
    '7z' => 'application/x-7z-compressed',
    _ => 'application/octet-stream',
  };
}

/// Resolves a file type without trusting the Android picker MIME alone.
/// Known filename extensions avoid I/O; extensionless provider results only
/// read a small prefix before the caller reopens the upload stream.
Future<String> resolveMobileFileContentType({
  required String fileName,
  required Stream<List<int>> Function() openRead,
}) async {
  final extension = fileName.contains('.') ? fileName.split('.').last : '';
  final namedType = mobileFileContentType(extension);
  if (namedType != 'application/octet-stream') return namedType;

  final prefix = <int>[];
  await for (final chunk in openRead()) {
    final remaining = 512 - prefix.length;
    if (remaining <= 0) break;
    prefix.addAll(chunk.length <= remaining ? chunk : chunk.take(remaining));
    if (prefix.length >= 512) break;
  }
  return mobileImageContentTypeFromHeader(prefix) ?? namedType;
}

String? mobileImageContentTypeFromHeader(List<int> bytes) {
  bool startsWith(List<int> signature) {
    if (bytes.length < signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    return true;
  }

  if (startsWith(const [0xFF, 0xD8, 0xFF])) return 'image/jpeg';
  if (startsWith(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])) {
    return 'image/png';
  }
  if (bytes.length >= 12 &&
      ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
      ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WEBP') {
    return 'image/webp';
  }
  if (startsWith(ascii.encode('GIF87a')) ||
      startsWith(ascii.encode('GIF89a'))) {
    return 'image/gif';
  }
  if (bytes.length >= 12 &&
      ascii.decode(bytes.sublist(4, 8), allowInvalid: true) == 'ftyp') {
    final brand = ascii
        .decode(bytes.sublist(8, 12), allowInvalid: true)
        .toLowerCase();
    if ({
      'heic',
      'heix',
      'hevc',
      'hevx',
      'heim',
      'heis',
      'hevm',
      'hevs',
      'mif1',
      'msf1',
    }.contains(brand)) {
      return 'image/heic';
    }
  }
  final text = utf8
      .decode(bytes, allowMalformed: true)
      .trimLeft()
      .toLowerCase();
  if (text.startsWith('<svg') ||
      (text.startsWith('<?xml') && text.contains('<svg'))) {
    return 'image/svg+xml';
  }
  return null;
}
