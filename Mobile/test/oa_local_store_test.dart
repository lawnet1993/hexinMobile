import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/storage/im_cache_cipher.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/oa_attachment_file_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/oa_local_store.dart';
import 'package:hexing_terminal_mobile/features/todos/domain/approval_form_calculation.dart';
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
            bytes: [],
            storedFile: OaStoredAttachment(
              token: 'opaque-token',
              fileName: 'receipt.pdf',
              contentType: 'application/pdf',
              length: 4,
              sha256: 'fixture-sha256',
            ),
            storageOwnerId: 'draft-1',
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
    expect(restored?.attachments.single.bytes, isEmpty);
    expect(restored?.attachments.single.size, 4);
    expect(restored?.attachments.single.storedFile?.token, 'opaque-token');
    expect(restored?.updatedAt, updatedAt);
  });

  test(
    'exact calculation values survive encrypted SQLite close and reopen',
    () async {
      final fields = [
        const ApprovalFormCalculationField(
          id: 'input',
          label: '原始费用',
          type: 'amount',
        ),
        const ApprovalFormCalculationField(
          id: 'amount',
          label: '请款金额',
          type: 'amount',
          calculation: ApprovalFormCalculation(
            expression: 'input + 0.01',
            scale: 2,
            roundingMode: 'half_up',
          ),
        ),
        const ApprovalFormCalculationField(
          id: 'cost',
          label: '成本',
          type: 'amount',
          calculation: ApprovalFormCalculation(
            expression: 'amount - input',
            scale: 2,
            roundingMode: 'half_up',
          ),
        ),
      ];
      final result = evaluateApprovalFormCalculations(
        fields: fields,
        sourceValues: const {'input': '90071992547409.92'},
      );
      expect(result.errors, isEmpty);
      await store.close();
      final cipher = AesGcmImCacheCipher(
        (_) async => List<int>.generate(32, (i) => i),
      );
      store = OaLocalStore.withOptions(
        databaseFactoryFfi,
        () async => '${directory.path}/oa.db',
        cipher,
      );
      await store.saveDraft(
        'precision-account',
        OaApprovalDraft(
          id: 'precision-draft',
          applicationKey: 'precision',
          templateId: 'precision',
          workflowKey: 'precision',
          title: 'AI-UAT 精度',
          formData: result.values,
          updatedAt: DateTime.utc(2026, 9, 3),
        ),
      );
      await store.close();
      final database = await databaseFactoryFfi.openDatabase(
        '${directory.path}/oa.db',
      );
      final raw =
          (await database.query('oa_approval_drafts')).single['form_data_json']
              as String;
      expect(cipher.isProtected(raw), isTrue);
      expect(raw.contains('90071992547409.93'), isFalse);
      await database.close();
      store = OaLocalStore.withOptions(
        databaseFactoryFfi,
        () async => '${directory.path}/oa.db',
        cipher,
      );
      final restored = await store.readDraftForTemplate(
        'precision-account',
        'precision',
      );
      expect(restored?.formData, result.values);
      expect(restored?.formData['amount'], '90071992547409.93');
      expect(restored?.formData['cost'], 0.01);
      expect(
        await store.readDraftForTemplate('different-account', 'precision'),
        isNull,
      );
      expect(
        evaluateApprovalFormCalculations(
          fields: fields,
          sourceValues: restored!.formData,
        ).values,
        result.values,
      );
    },
  );

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

  test('sync health is account-scoped and counts unsent OA state', () async {
    await store.applySyncBatch(
      accountId: 'account-a',
      events: [
        OaSyncEvent(
          id: 'event-7',
          sequence: 7,
          type: 'oa.approval.updated',
          payloadJson: '{"requestId":"approval-7"}',
          createdAt: DateTime.utc(2026, 9, 5),
        ),
      ],
      refreshedCaches: const {},
    );
    await store.enqueue(
      'account-a',
      id: 'command-1',
      idempotencyKey: 'command-1',
      commandType: 'submit-approval',
      payload: const {'title': 'AI-UAT'},
    );
    await store.enqueueNotificationRead('account-a', 'notice-1');

    final accountA = await store.syncHealth('account-a');
    final accountB = await store.syncHealth('account-b');
    expect(accountA.appliedSequence, 7);
    expect(accountA.pendingCommandCount, 1);
    expect(accountA.pendingNotificationReadCount, 1);
    expect(accountB.appliedSequence, 0);
    expect(accountB.pendingCommandCount, 0);
    expect(accountB.pendingNotificationReadCount, 0);
  });

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
          OaLocalStore.notificationPageCacheKey: '{"items":[{"id":"notice-1"}],"nextCursor":"cursor-2","hasMore":true}',
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
      expect(
        await store.readObject(
          'account-a',
          OaLocalStore.notificationPageCacheKey,
        ),
        {
          'items': [
            {'id': 'notice-1'},
          ],
          'nextCursor': 'cursor-2',
          'hasMore': true,
        },
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

  test('sync encryption does not hold the SQLite transaction lock', () async {
    final cipher = _BlockingProtectCipher();
    final blockingStore = OaLocalStore.withOptions(
      databaseFactoryFfi,
      () async => '${directory.path}/oa-blocking.db',
      cipher,
    );
    addTearDown(blockingStore.close);

    final sync = blockingStore.applySyncBatch(
      accountId: 'account-a',
      events: [
        OaSyncEvent(
          sequence: 1,
          id: 'event-1',
          type: 'oa.notification.created',
          payloadJson: 'block-before-transaction',
          createdAt: DateTime.utc(2026, 9, 1),
        ),
      ],
      refreshedCaches: const {},
    );
    await cipher.entered.future;

    await blockingStore
        .writeObject('account-a', 'parallel-write', const {'ok': true})
        .timeout(const Duration(seconds: 1));

    cipher.release.complete();
    await sync;
    expect(
      await blockingStore.readObject('account-a', 'parallel-write'),
      const {'ok': true},
    );
  });
}

final class _BlockingProtectCipher implements ImCacheCipher {
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  bool get isEnabled => true;

  @override
  bool isProtected(String value) => false;

  @override
  Future<String> protect(String accountId, String value) async {
    if (value == 'block-before-transaction') {
      if (!entered.isCompleted) entered.complete();
      await release.future;
    }
    return value;
  }

  @override
  Future<String> reveal(String accountId, String value) async => value;
}
