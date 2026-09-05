import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/im_cache_cipher.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/oa_attachment_file_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/oa_local_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  test(
    'draft stores encrypted file reference and streams original bytes',
    () async {
      final root = await Directory.systemTemp.createTemp('oa-stream-storage-');
      final databasePath = '${root.path}/oa.db';
      FlutterSecureStorage.setMockInitialValues({});
      final sessions = SecureSessionStore();
      await sessions.saveSession(
        const MobileSession(
          accessToken: 'fixture-token',
          deviceId: 'fixture-device',
          userId: 'fixture-account',
          displayName: 'Fixture',
          username: 'fixture',
          policySignatureKey: '',
          imApiUrl: '',
          oaApiUrl: 'http://127.0.0.1:1',
        ),
      );
      final localStore = OaLocalStore.withOptions(
        databaseFactoryFfi,
        () async => databasePath,
        const PlainImCacheCipher(),
      );
      final fileStore = OaAttachmentFileStore(
        keyLoader: sessions.readOrCreateImCacheKey,
        directoryLoader: () async => Directory('${root.path}/files'),
      );
      final repository = OaRepository(
        CollaborationClient(sessions),
        sessions,
        localStore,
        attachmentFileStore: fileStore,
      );
      final source = Uint8List.fromList(
        List<int>.generate(2 * 1024 * 1024 + 73, (index) => index % 251),
      );

      try {
        final saved = await repository.saveDraft(
          id: 'draft-stream',
          applicationKey: 'expense',
          template: const OaApprovalTemplate(
            id: 'template-stream',
            name: '报销审批',
            category: '费用',
            workflowKey: 'expense-flow',
          ),
          title: 'AI-UAT-流式附件',
          formData: const {'reason': 'stream'},
          attachments: [
            OaLocalAttachment.fromJson({
              'id': 'attachment-stream',
              'fileName': 'evidence.bin',
              'contentType': 'application/octet-stream',
              'bytesBase64': base64Encode(source),
              'formFieldId': 'proof',
              'previewBytesBase64': base64Encode(const [1, 2, 3]),
            }),
          ],
        );
        final attachment = saved.attachments.single;
        expect(attachment.bytes, isEmpty);
        expect(attachment.size, source.length);
        expect(attachment.storedFile, isNotNull);
        expect(attachment.storageOwnerId, 'draft-stream');
        expect(await repository.readLocalAttachmentBytes(attachment), source);

        await localStore.close();
        final database = await databaseFactoryFfi.openDatabase(databasePath);
        final row = (await database.query('oa_approval_drafts')).single;
        final attachmentJson = row['attachments_json']?.toString() ?? '';
        expect(attachmentJson, contains('storedFile'));
        expect(attachmentJson, contains('storedPreviewFile'));
        expect(attachmentJson, isNot(contains('bytesBase64')));
        expect(attachmentJson, isNot(contains('previewBytesBase64')));
        expect(attachmentJson, isNot(contains(base64Encode(source))));
        await database.close();

        final reopenedStore = OaLocalStore.withOptions(
          databaseFactoryFfi,
          () async => databasePath,
          const PlainImCacheCipher(),
        );
        final reopenedRepository = OaRepository(
          CollaborationClient(sessions),
          sessions,
          reopenedStore,
          attachmentFileStore: fileStore,
        );
        final restored = await reopenedRepository.draftForTemplate(
          'template-stream',
        );
        expect(restored, isNotNull);
        expect(
          await reopenedRepository.readLocalAttachmentBytes(
            restored!.attachments.single,
          ),
          source,
        );
        await reopenedRepository.deleteDraft('draft-stream');
        await expectLater(
          reopenedRepository.readLocalAttachmentBytes(
            restored.attachments.single,
          ),
          throwsStateError,
        );
        await reopenedStore.close();
      } finally {
        await localStore.close();
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );

  test('stored attachment cannot be opened under another owner', () async {
    final root = await Directory.systemTemp.createTemp('oa-owner-isolation-');
    final store = OaAttachmentFileStore(
      keyLoader: (_) async => List<int>.generate(32, (index) => index),
      directoryLoader: () async => root,
    );
    try {
      final file = await store.writeBytes(
        accountId: 'account-a',
        ownerId: 'draft-a',
        fileName: 'proof.txt',
        contentType: 'text/plain',
        bytes: Uint8List.fromList(utf8.encode('private-proof')),
      );
      await expectLater(
        store.readBytes(accountId: 'account-a', ownerId: 'draft-b', file: file),
        throwsA(anything),
      );
    } finally {
      if (await root.exists()) await root.delete(recursive: true);
    }
  });
}
