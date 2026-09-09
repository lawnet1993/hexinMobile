// Explicit acceptance-only entry. Never imported by normal main. Observes the
// real commit-before-ACK seam; no fake events, cursor writes, or API mutations.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:hexing_terminal_mobile/app.dart';
import 'package:hexing_terminal_mobile/core/config/app_environment.dart';
import 'package:hexing_terminal_mobile/core/diagnostics/mobile_startup_diagnostics.dart';
import 'package:hexing_terminal_mobile/core/network/collaboration_client.dart';
import 'package:hexing_terminal_mobile/core/storage/secure_session_store.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_member_presence.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const conversationId = '245e652d-14be-4c29-a7aa-57b7659fa4e6';
  final session = await SecureSessionStore().readSession();
  if (kReleaseMode ||
      session?.username != 'test03' ||
      Uri.tryParse(session?.imApiUrl ?? '')?.host != 'api.sfhkh.com' ||
      Uri.parse(AppEnvironment.controlPlaneUrl).host != 'api.sfhkh.com') {
    throw StateError('Explicit test03 acceptance session required');
  }
  final timer = Stopwatch()..start();
  final directory = await getTemporaryDirectory();
  final log = File(
    '${directory.path}/ai-uat-im-batch-${DateTime.now().microsecondsSinceEpoch}.jsonl',
  );
  final startup = MobileStartupDiagnostics.install();
  PaintingBinding.instance.imageCache
    ..maximumSize = 120
    ..maximumSizeBytes = 48 * 1024 * 1024;
  var observed = 0;
  runApp(
    ProviderScope(
      overrides: [
        imRepositoryProvider.overrideWith((ref) {
          final store = ref.read(imLocalStoreProvider);
          return ImRepository(
            ref.read(collaborationClientProvider),
            ref.read(secureSessionStoreProvider),
            store,
            memberPresence: () => ref.mounted
                ? ref.read(imMemberPresenceProjectionProvider.notifier)
                : null,
            beforeEventAck: (sequence, events) async {
              if (observed >= 20) return;
              final messages = events
                  .where((event) => event.type == 'message.created')
                  .map(
                    (event) => ImMessage.fromJson(
                      (jsonDecode(event.payloadJson) as Map)
                          .cast<String, Object?>(),
                    ),
                  )
                  .where((message) => message.conversationId == conversationId)
                  .toList();
              if (messages.isEmpty) return;
              final persisted = await store.readMessages(
                session!.userId,
                conversationId,
                limit: 1000,
              );
              final conversation = (await store.readBootstrap(session.userId))!
                  .conversations
                  .singleWhere((item) => item.id == conversationId);
              final marker = RegExp(r'^AI-UAT-701-BATCH-(\d{4})$');
              final numbers = persisted
                  .map((message) => marker.firstMatch(message.content))
                  .whereType<RegExpMatch>()
                  .map((match) => int.parse(match.group(1)!))
                  .toList();
              final ordered = numbers.asMap().entries.every(
                (entry) => entry.value == entry.key + 1,
              );
              final committedIds = persisted
                  .map((message) => message.id)
                  .toSet();
              final record = <String, Object?>{
                'stage': 'committed_before_ack',
                'batch': ++observed,
                'elapsedMs': timer.elapsedMilliseconds,
                'at': DateTime.now().toUtc().toIso8601String(),
                'eventCount': events.length,
                'firstEventSequence': events
                    .map((event) => event.sequence)
                    .reduce((a, b) => a < b ? a : b),
                'lastEventSequence': sequence,
                'appliedCursor': await store.lastEventSequence(
                  session.userId,
                  session.syncDeviceId,
                ),
                'ackedCursor': await store.lastAckedEventSequence(
                  session.userId,
                  session.syncDeviceId,
                ),
                'batchTestMessages': messages.length,
                'batchMessagesPersisted': messages.every(
                  (message) => committedIds.contains(message.id),
                ),
                'persistedCount': persisted.length,
                'uniqueServerIds': committedIds.length,
                'uniqueClientIds': persisted
                    .map((message) => message.clientMessageId)
                    .toSet()
                    .length,
                'markerCount': numbers.length,
                'markersOrderedFromOne': ordered,
                'lastMarker': numbers.isEmpty ? 0 : numbers.last,
                'lastMessage': conversation.lastMessageSequence,
                'lastRead': conversation.lastReadSequence,
                'unread': conversation.unreadCount,
              };
              // Numeric metadata only. No credentials, device keys, payloads or URLs.
              await log.writeAsString(
                '${jsonEncode(record)}\n',
                mode: FileMode.append,
                flush: true,
              );
              debugPrint('AI_UAT_IM_BATCH ${jsonEncode(record)}');
            },
          );
        }),
      ],
      child: const HexingMobileApp(),
    ),
  );
  startup?.mark(MobileStartupStage.runAppReturned);
}
