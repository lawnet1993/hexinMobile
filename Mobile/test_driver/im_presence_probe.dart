// Read-only diagnostic entrypoint; never imported by the normal application.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/main.dart' as app;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode && const bool.fromEnvironment('UAT_VERIFY_PRESENCE')) {
    try {
      debugPrint('AI_UAT_PRESENCE ${jsonEncode(await inspectPresence())}');
    } catch (_) {
      debugPrint('AI_UAT_PRESENCE {"probe":"unavailable"}');
    }
  }
  await app.main();
}

Future<Map<String, Object?>> inspectPresence() async {
  final store = SecureSessionStore();
  final session = await store.readSession();
  if (session == null ||
      session.username != 'test03' ||
      Uri.parse(session.imApiUrl).host != 'api.sfhkh.com') {
    throw StateError('Authorized test session required');
  }
  const conversation = '2a2ea21f-2ad6-49b3-b3da-407d1e7e4136';
  const peer = '63bb07f7-89dc-449e-9e49-4b528f5215b7';
  final dio = await CollaborationClient(store).forIm(forSession: session);
  dio.options.followRedirects = false;
  dio.options.validateStatus = (_) => true;
  final result = <String, Object?>{
    'checkedAt': DateTime.now().toUtc().toIso8601String(),
  };
  Map<String, Object?> member(Object? value) {
    final row = value is Map ? value : const {};
    return {
      'isOnline': row['isOnline'] is bool ? row['isOnline'] : null,
      'lastSeenAt': DateTime.tryParse(row['lastSeenAt']?.toString() ?? '')
          ?.toUtc()
          .toIso8601String(),
      'found': row['id'] == peer,
    };
  }

  try {
    for (final name in [
      'bootstrap',
      'members',
      'presence',
      'presence-repeat',
    ]) {
      final path = name == 'bootstrap'
          ? '/api/im/bootstrap'
          : '/api/im/conversations/$conversation/${name.startsWith('presence') ? 'presence' : 'members'}';
      final response = await dio.get<Object?>(path);
      final body = response.data;
      final item = <String, Object?>{'status': response.statusCode};
      if (name.startsWith('presence') && body is Map) {
        item.addAll({
          'type': body['type'] == 'direct' ? 'direct' : 'other',
          'conversationMatches': body['conversationId'] == conversation,
          'peerOnline': body['peerOnline'] is bool ? body['peerOnline'] : null,
          'peerLastSeenAt': DateTime.tryParse(
            body['peerLastSeenAt']?.toString() ?? '',
          )?.toUtc().toIso8601String(),
          'serverTime': DateTime.tryParse(body['serverTime']?.toString() ?? '')
              ?.toUtc()
              .toIso8601String(),
        });
      } else {
        final rows = name == 'bootstrap' && body is Map
            ? body['contacts']
            : body;
        if (rows is List) {
          item['peer'] = member(
            rows.whereType<Map>().where((row) => row['id'] == peer).firstOrNull,
          );
        }
      }
      result[name] = item;
    }
    return result;
  } finally {
    dio.close(force: true);
  }
}
