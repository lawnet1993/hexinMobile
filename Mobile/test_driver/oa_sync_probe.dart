// Temporary profile-only entrypoint. Read-only corroboration of UI-created
// AI-UAT requests using the installation's existing session; never logs secrets.
// Build explicitly with --target test_driver/oa_sync_probe.dart and
// --dart-define=UAT_OA_REQUEST_ID=<test request UUID>. Normal main.dart excludes it.
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import 'package:hexing_terminal_mobile/core/config/app_environment.dart';
import 'package:hexing_terminal_mobile/core/storage/im_cache_cipher.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/main.dart' as app;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode) {
    try {
      final result = await inspectTestRequest();
      // Only the explicitly constructed whitelist below reaches this log.
      final json = jsonEncode(result);
      final count = (json.length / 450).ceil();
      for (var part = 0; part < count; part++) {
        final end = (part + 1) * 450;
        debugPrint(
          'AI_UAT_OA_PROBE ${jsonEncode({'part': part, 'count': count, 'data': json.substring(part * 450, end < json.length ? end : json.length)})}',
        );
      }
    } catch (error) {
      debugPrint(
        'AI_UAT_OA_PROBE ${jsonEncode({'errorType': error.runtimeType.toString()})}',
      );
    }
  }
  await app.main();
}

Future<Map<String, Object?>> inspectTestRequest() async {
  const requestId = String.fromEnvironment('UAT_OA_REQUEST_ID');
  if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(requestId)) {
    throw StateError('Explicit test request required');
  }
  final session = await SecureSessionStore().readSession();
  if (session == null ||
      !RegExp(r'^test(0[1-9]|10)$').hasMatch(session.username)) {
    throw StateError('Numbered test session required');
  }
  final origin = Uri.parse(session.oaApiUrl);
  if (!const ['http', 'https'].contains(origin.scheme) ||
      origin.host != 'api.sfhkh.com' ||
      origin.userInfo.isNotEmpty ||
      Uri.parse(AppEnvironment.controlPlaneUrl).host != origin.host) {
    throw StateError('Authorized test origin required');
  }
  final dio = Dio(
    BaseOptions(
      baseUrl: '${origin.scheme}://${origin.authority}',
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 15),
      followRedirects: false,
      headers: {
        'Authorization': 'Bearer ${session.accessToken}',
        'X-Device-Id': session.deviceId,
        'X-Terminal-Device-Id': session.deviceId,
        'X-Terminal-Account-Id': session.userId,
      },
    ),
  );
  Database? database;
  try {
    final detail = await dio.get<Map<String, dynamic>>(
      '/api/oa/approval-requests/$requestId',
    );
    final body = detail.data ?? {};
    if (!(body['formDataJson']?.toString() ?? '').contains('AI-UAT-')) {
      throw StateError('Only UI-created AI-UAT records may be inspected');
    }
    final result = <String, Object?>{
      'checkedAt': DateTime.now().toUtc().toIso8601String(),
      'account': session.username,
      'requestId': requestId,
      'detailHttpStatus': detail.statusCode,
      'status': body['status'],
      'version': body['version'],
      'updatedAt': body['updatedAt'],
    };
    final events = <Map<String, Object?>>[];
    final notificationResponse = await dio.get<Map<String, dynamic>>(
      '/api/oa/notifications/page',
      queryParameters: {'take': 200, 'unreadOnly': false},
    );
    final targetNotifications =
        (notificationResponse.data?['items'] as List? ?? [])
            .whereType<Map>()
            .where(
              (item) => targetOf(item.cast<String, dynamic>()) == requestId,
            )
            .toList();
    result['notifications'] = {
      'httpStatus': notificationResponse.statusCode,
      'hasMore': notificationResponse.data?['hasMore'],
      'items': targetNotifications
          .map(
            (item) => {
              'id': item['id'],
              'type': item['type'],
              'isRead': item['isRead'],
              'readAt': item['readAt'],
              'createdAt': item['createdAt'],
            },
          )
          .toList(),
    };
    final types = <String, int>{};
    var cursor = 0;
    var latest = 0;
    var complete = false;
    for (var page = 0; page < 10; page++) {
      final response = await dio.get<Map<String, dynamic>>(
        '/api/oa/sync/events',
        queryParameters: {
          'afterSequence': cursor,
          'waitSeconds': 0,
          'take': 200,
        },
      );
      final data = response.data ?? {};
      latest = (data['latestSequence'] as num?)?.toInt() ?? latest;
      final batch = (data['events'] as List? ?? []).whereType<Map>();
      var next = cursor;
      for (final event in batch) {
        final sequence = (event['sequence'] as num?)?.toInt() ?? 0;
        if (sequence > next) next = sequence;
        final type = event['type']?.toString() ?? '';
        types[type] = (types[type] ?? 0) + 1;
        final payload = decodePayload(event['payloadJson']);
        if (targetOf(payload) == requestId) {
          events.add({
            'sequence': sequence,
            'id': event['id'],
            'type': type,
            'createdAt': event['createdAt'],
            'requestId': requestId,
            'payloadFields': payload.keys.toList(),
          });
        }
      }
      if (next == cursor || next >= latest) {
        complete = true;
        break;
      }
      cursor = next;
    }
    result['server'] = {
      'latestSequence': latest,
      'complete': complete,
      'typeCounts': types,
      'matchingEvents': events,
    };

    // Read existing encryption key, never create/rotate it. No key or plaintext
    // payload is exported, and no local cursor/cache is changed by this probe.
    const storage = FlutterSecureStorage();
    final suffix = base64Url
        .encode(utf8.encode(session.userId))
        .replaceAll('=', '');
    final encodedKey = await storage.read(
      key: AppEnvironment.secureStorageKey('mobile.im.cache-key.v1.$suffix'),
    );
    if (encodedKey == null) throw StateError('Existing cache key required');
    final cipher = AesGcmImCacheCipher((_) async => base64Decode(encodedKey));
    database = await openDatabase(
      path.join(
        await getDatabasesPath(),
        AppEnvironment.databaseFileName('oa'),
      ),
      readOnly: true,
      singleInstance: false,
    );
    final rows = await database.query(
      'oa_event_inbox',
      where: 'account_id = ?',
      whereArgs: [session.userId],
      orderBy: 'sequence',
    );
    final localEvents = <Map<String, Object?>>[];
    for (final row in rows) {
      final payload = decodePayload(
        await cipher.reveal(
          session.userId,
          row['payload_json']?.toString() ?? '{}',
        ),
      );
      if (targetOf(payload) == requestId) {
        localEvents.add({
          'sequence': row['sequence'],
          'id': row['event_id'],
          'type': row['type'],
          'createdAt': row['created_at'],
          'appliedAt': row['applied_at'],
          'requestId': requestId,
        });
      }
    }
    result['local'] = {
      'cursors': await database.query(
        'oa_sync_state',
        columns: ['state_key', 'value', 'updated_at'],
        where: "account_id = ? AND state_key = 'last-event-sequence'",
        whereArgs: [session.userId],
      ),
      'eventCount': rows.length,
      'matchingEvents': localEvents,
    };
    final receiptTable = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='oa_notification_reads'",
    );
    final ids = targetNotifications
        .map((item) => item['id'])
        .whereType<String>()
        .toList();
    if (receiptTable.isNotEmpty && ids.isNotEmpty) {
      result['localReadReceipts'] = await database.query(
        'oa_notification_reads',
        columns: ['notification_id', 'read_at', 'state', 'attempts'],
        where:
            "account_id = ? AND notification_id IN (${List.filled(ids.length, '?').join(',')})",
        whereArgs: [session.userId, ...ids],
      );
    }
    return result;
  } finally {
    await database?.close();
    dio.close(force: true);
  }
}

Map<String, dynamic> decodePayload(Object? raw) {
  try {
    final decoded = jsonDecode(raw?.toString() ?? '{}');
    return decoded is Map ? decoded.cast<String, dynamic>() : {};
  } on FormatException {
    return {};
  }
}

Object? targetOf(Map<String, dynamic> payload) =>
    payload['requestId'] ??
    payload['RequestId'] ??
    payload['approvalRequestId'] ??
    payload['ApprovalRequestId'];
