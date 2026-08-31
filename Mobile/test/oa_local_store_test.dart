import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/storage/im_cache_cipher.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/oa_local_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Directory directory;
  late OaLocalStore store;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('oa-local-store-');
    store = OaLocalStore.withOptions(
      databaseFactoryFfi,
      () async => '${directory.path}/oa.db',
      const PlainImCacheCipher(),
    );
  });

  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });

  test(
    'cache snapshots are isolated by account and can be invalidated',
    () async {
      await store.writeObject('account-a', OaLocalStore.bootstrapCacheKey, {
        'currentMember': {'id': 'member-a'},
      });
      await store.writeObject('account-b', OaLocalStore.bootstrapCacheKey, {
        'currentMember': {'id': 'member-b'},
      });

      expect(
        (await store.readObject(
          'account-a',
          OaLocalStore.bootstrapCacheKey,
        ))?['currentMember'],
        {'id': 'member-a'},
      );
      expect(
        await store.cacheUpdatedAt('account-a', OaLocalStore.bootstrapCacheKey),
        isNotNull,
      );

      await store.invalidate('account-a', [OaLocalStore.bootstrapCacheKey]);
      expect(
        await store.readObject('account-a', OaLocalStore.bootstrapCacheKey),
        isNull,
      );
      expect(
        await store.readObject('account-b', OaLocalStore.bootstrapCacheKey),
        isNotNull,
      );
    },
  );

  test('draft survives reopen and preserves dynamic form values', () async {
    final updatedAt = DateTime.utc(2026, 8, 22, 10, 30);
    await store.saveDraft(
      'account-a',
      OaApprovalDraft(
        id: 'draft-1',
        applicationKey: 'expense',
        templateId: 'template-1',
        workflowKey: 'expense-flow',
        title: '八月报销',
        formData: const {'amount': 128.5, 'reason': '客户拜访'},
        attachments: const [
          OaLocalAttachment(
            id: 'local-file-1',
            fileName: 'receipt.pdf',
            contentType: 'application/pdf',
            bytes: [1, 2, 3, 4],
          ),
        ],
        updatedAt: updatedAt,
      ),
    );
    await store.close();

    store = OaLocalStore.withOptions(
      databaseFactoryFfi,
      () async => '${directory.path}/oa.db',
      const PlainImCacheCipher(),
    );
    final restored = await store.readDraftForTemplate(
      'account-a',
      'template-1',
    );

    expect(restored?.id, 'draft-1');
    expect(restored?.title, '八月报销');
    expect(restored?.formData['amount'], 128.5);
    expect(restored?.attachments.single.fileName, 'receipt.pdf');
    expect(restored?.attachments.single.bytes, [1, 2, 3, 4]);
    expect(restored?.updatedAt, updatedAt);
  });

  test('version 1 draft database upgrades without losing old drafts', () async {
    await store.close();
    final databasePath = '${directory.path}/oa.db';
    final database = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (database, _) async {
          await database.execute('''
            CREATE TABLE oa_approval_drafts (
              account_id TEXT NOT NULL,
              id TEXT NOT NULL,
              application_key TEXT NOT NULL,
              template_id TEXT NOT NULL,
              workflow_key TEXT NOT NULL,
              title TEXT NOT NULL,
              form_data_json TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              PRIMARY KEY (account_id, id)
            )
          ''');
          await database.insert('oa_approval_drafts', {
            'account_id': 'account-a',
            'id': 'legacy-draft',
            'application_key': 'leave',
            'template_id': 'leave-template',
            'workflow_key': 'leave-flow',
            'title': '旧请假草稿',
            'form_data_json': '{"days":1}',
            'updated_at': DateTime.utc(2026, 8, 20).toIso8601String(),
          });
        },
      ),
    );
    await database.close();

    store = OaLocalStore.withOptions(
      databaseFactoryFfi,
      () async => databasePath,
      const PlainImCacheCipher(),
    );
    final restored = await store.readDraftForTemplate(
      'account-a',
      'leave-template',
    );

    expect(restored?.title, '旧请假草稿');
    expect(restored?.attachments, isEmpty);
  });

  test(
    'outbox retries transient failures and keeps permanent failures visible',
    () async {
      final pending = await store.enqueue(
        'account-a',
        id: 'outbox-1',
        idempotencyKey: 'request-1',
        commandType: 'submit-approval',
        payload: const {'title': '离线请假', 'clientRequestId': 'request-1'},
      );
      expect(await store.dueOutbox('account-a'), hasLength(1));

      await store.updateOutboxPayload('account-a', pending.id, {
        ...pending.payload,
        'attachmentIds': ['server-file-1'],
        'pendingAttachments': const [],
      });
      expect(
        (await store.readOutbox('account-a')).single.payload['attachmentIds'],
        ['server-file-1'],
      );

      await store.markOutboxFailed(
        'account-a',
        pending,
        'network unavailable',
        permanent: false,
      );
      final retrying = (await store.readOutbox('account-a')).single;
      expect(retrying.state, 'pending');
      expect(retrying.attempts, 1);
      expect(retrying.lastError, 'network unavailable');

      await store.markOutboxFailed(
        'account-a',
        retrying,
        'validation rejected',
        permanent: true,
      );
      final failed = (await store.readOutbox('account-a')).single;
      expect(failed.state, 'failed');
      expect(failed.attempts, 2);
      expect(failed.lastError, 'validation rejected');
    },
  );

  test(
    'event inbox, refreshed projections and cursor advance atomically',
    () async {
      final event = OaSyncEvent(
        sequence: 12,
        id: 'event-12',
        type: 'oa.notification.created',
        payloadJson: '{"notificationId":"notice-1"}',
        createdAt: DateTime.utc(2026, 8, 22, 11),
      );
      await store.applySyncBatch(
        accountId: 'account-a',
        events: [event, event],
        refreshedCaches: const {
          OaLocalStore.notificationsCacheKey: '[{"id":"notice-1"}]',
        },
      );

      expect(await store.lastEventSequence('account-a'), 12);
      expect(
        (await store.readList(
          'account-a',
          OaLocalStore.notificationsCacheKey,
        ))?.single,
        {'id': 'notice-1'},
      );

      await store.applySyncBatch(
        accountId: 'account-a',
        events: [
          OaSyncEvent(
            sequence: 10,
            id: 'event-10',
            type: 'oa.stale',
            payloadJson: '{}',
            createdAt: DateTime.utc(2026, 8, 22, 10),
          ),
        ],
        refreshedCaches: const {},
      );
      expect(await store.lastEventSequence('account-a'), 12);
    },
  );
}
