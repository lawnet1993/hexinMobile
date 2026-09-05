import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'im_outbox_file_store.dart';

typedef OaAttachmentDirectoryLoader = Future<Directory> Function();

/// Metadata persisted in the encrypted OA database instead of attachment bytes.
final class OaStoredAttachment {
  const OaStoredAttachment({
    required this.token,
    required this.fileName,
    required this.contentType,
    required this.length,
    required this.sha256,
  });

  factory OaStoredAttachment.fromJson(Map<String, Object?> json) =>
      OaStoredAttachment(
        token: json['token']?.toString() ?? '',
        fileName: json['fileName']?.toString() ?? '',
        contentType: json['contentType']?.toString() ?? '',
        length: _integer(json['length']),
        sha256: json['sha256']?.toString() ?? '',
      );

  final String token;
  final String fileName;
  final String contentType;
  final int length;
  final String sha256;

  Map<String, Object?> toJson() => {
    'token': token,
    'fileName': fileName,
    'contentType': contentType,
    'length': length,
    'sha256': sha256,
  };

  ImOutboxStoredFile get _delegate => ImOutboxStoredFile(
    token: token,
    role: 'oa-attachment',
    fileName: fileName,
    contentType: contentType,
    length: length,
    sha256: sha256,
  );

  static OaStoredAttachment _fromDelegate(ImOutboxStoredFile file) =>
      OaStoredAttachment(
        token: file.token,
        fileName: file.fileName,
        contentType: file.contentType,
        length: file.length,
        sha256: file.sha256,
      );
}

/// Account-scoped encrypted file storage for OA drafts and queued requests.
///
/// The proven streaming AES-GCM container used by the IM outbox is reused,
/// while OA gets a separate directory and owner namespace. SQLite therefore
/// contains only encrypted metadata and a small optional thumbnail.
final class OaAttachmentFileStore {
  OaAttachmentFileStore({
    required Future<List<int>> Function(String accountId) keyLoader,
    OaAttachmentDirectoryLoader? directoryLoader,
  }) : _delegate = ImOutboxFileStore(
         keyLoader: keyLoader,
         directoryLoader: directoryLoader ?? _defaultDirectory,
       );

  final ImOutboxFileStore _delegate;

  Future<OaStoredAttachment> writeBytes({
    required String accountId,
    required String ownerId,
    required String fileName,
    required String contentType,
    required Uint8List bytes,
  }) async => OaStoredAttachment._fromDelegate(
    await _delegate.writeBytes(
      accountId: accountId,
      clientMessageId: _owner(ownerId),
      role: 'oa-attachment',
      fileName: fileName,
      contentType: contentType,
      bytes: bytes,
    ),
  );

  Future<OaStoredAttachment> writeStream({
    required String accountId,
    required String ownerId,
    required String fileName,
    required String contentType,
    required int clearLength,
    required Stream<List<int>> source,
  }) async => OaStoredAttachment._fromDelegate(
    await _delegate.writeStream(
      accountId: accountId,
      clientMessageId: _owner(ownerId),
      role: 'oa-attachment',
      fileName: fileName,
      contentType: contentType,
      clearLength: clearLength,
      source: source,
    ),
  );

  Stream<List<int>> openRead({
    required String accountId,
    required String ownerId,
    required OaStoredAttachment file,
  }) => _delegate.openRead(
    accountId: accountId,
    clientMessageId: _owner(ownerId),
    file: file._delegate,
  );

  Future<Uint8List> readBytes({
    required String accountId,
    required String ownerId,
    required OaStoredAttachment file,
  }) => _delegate.readBytes(
    accountId: accountId,
    clientMessageId: _owner(ownerId),
    file: file._delegate,
  );

  Future<void> verify({
    required String accountId,
    required String ownerId,
    required OaStoredAttachment file,
  }) => _delegate.verify(
    accountId: accountId,
    clientMessageId: _owner(ownerId),
    file: file._delegate,
  );

  Future<void> deleteAll(
    String accountId,
    Iterable<OaStoredAttachment> files,
  ) => _delegate.deleteAll(accountId, files.map((file) => file._delegate));

  static String _owner(String ownerId) {
    if (ownerId.trim().isEmpty) {
      throw ArgumentError('OA attachment owner is required.');
    }
    return 'oa:$ownerId';
  }

  static Future<Directory> _defaultDirectory() async {
    try {
      return Directory(
        path.join(
          (await getApplicationSupportDirectory()).path,
          'oa-queued-attachments',
        ),
      );
    } on MissingPluginException {
      // Pure Dart/widget tests do not register path_provider. Tokens remain
      // account scoped and encrypted; production platforms use app support.
      return Directory(
        path.join(Directory.systemTemp.path, 'oa-queued-attachments-tests'),
      );
    }
  }
}

int _integer(Object? value) => switch (value) {
  int number => number,
  num number => number.toInt(),
  _ => int.tryParse(value?.toString() ?? '') ?? 0,
};
