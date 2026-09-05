import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_local_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory directory;
  late ImLocalStore store;
  late DateTime now;
  ImLocalStore open() => ImLocalStore(
    factory: databaseFactoryFfi,
    pathResolver: () async => '${directory.path}/im.db',
    clock: () => now,
  );
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('im-reconnect-');
    now = DateTime.utc(2026, 9, 2);
    store = open();
  });
  tearDown(() async {
    await store.close();
    await directory.delete(recursive: true);
  });
  Future<ImOutboxItem> fail(String account, String id, bool transport) async {
    await store.enqueueText(
      accountId: account,
      senderId: account,
      conversationId: id,
      clientMessageId: id,
      content: 'fixture $id',
    );
    final item = (await store.dueOutbox(account))
        .singleWhere((m) => m.clientMessageId == id);
    await store.markOutboxFailed(
      account,
      item,
      'same sanitized error',
      retryScheduled: true,
      retryOnConnectionChange: transport,
    );
    return item;
  }

  test('reopen recovers transport only, once, retaining FIFO and account isolation', () async {
    await fail('a', 'transport', true);
    now = now.add(const Duration(microseconds: 1));
    await store.enqueueText(
      accountId: 'a',
      senderId: 'a',
      conversationId: 'transport',
      clientMessageId: 'second',
      content: 'second',
    );
    await fail('a', 'http-500', false);
    await fail('b', 'other-account', true);
    expect(await store.dueOutbox('a'), isEmpty);
    await store.close();
    store = open();
    expect(await store.resumeNetworkOutbox('a'), 1);
    final due = await store.dueOutbox('a');
    expect(due.map((m) => m.clientMessageId), ['transport', 'second']);
    expect(due.first.attempts, 1);
    expect(due.first.content, 'fixture transport');
    expect(await store.dueOutbox('b'), isEmpty);
    expect(await store.resumeNetworkOutbox('a'), 0);
    expect(await store.readMessages('a', 'transport'), hasLength(2));
  });

  test(
    'a subsequent HTTP error removes the earlier transport wakeup flag',
    () async {
      final item = await fail('a', 'transport', true);
      await store.markOutboxFailed('a', item, 'HTTP 503', retryScheduled: true);
      expect(await store.resumeNetworkOutbox('a'), 0);
      expect(await store.dueOutbox('a'), isEmpty);
    },
  );

  test(
    'only typed transport failures qualify, not status, cancel or local errors',
    () {
      for (final type in DioExceptionType.values) {
        final error = DioException(
          requestOptions: RequestOptions(path: '/fixture'),
          type: type,
        );
        expect(
          isTransportImOutboxFailure(error),
          [
            DioExceptionType.connectionTimeout,
            DioExceptionType.sendTimeout,
            DioExceptionType.receiveTimeout,
            DioExceptionType.connectionError,
          ].contains(type),
          reason: type.name,
        );
      }
      for (final status in [401, 408, 409, 429, 500, 503]) {
        final options = RequestOptions(path: '/fixture');
        expect(
          isTransportImOutboxFailure(
            DioException(
              requestOptions: options,
              type: DioExceptionType.receiveTimeout,
              response: Response(requestOptions: options, statusCode: status),
            ),
          ),
          isFalse,
        );
      }
      expect(
        isTransportImOutboxFailure(StateError('local file invalid')),
        isFalse,
      );
    },
  );
}
