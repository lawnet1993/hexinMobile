// Explicit test-only entry point, never imported by lib/main.dart. Pauses only
// after the specified real message.created has committed and before its ACK.
// Kill via ADB after AI_UAT_IM_CHECKPOINT; restore normal APK before relaunch.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  const marker = String.fromEnvironment('UAT_IM_MESSAGE_MARKER');
  const conversationId = String.fromEnvironment('UAT_IM_CONVERSATION_ID');
  const requireSelfMention = bool.fromEnvironment(
    'UAT_IM_REQUIRE_SELF_MENTION',
  );
  final session = await SecureSessionStore().readSession();
  if (kReleaseMode ||
      !marker.startsWith('AI-UAT-') ||
      marker.length > 100 ||
      (conversationId.isNotEmpty &&
          !RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(conversationId)) ||
      (requireSelfMention && conversationId.isEmpty) ||
      session?.username != 'test03' ||
      Uri.tryParse(session?.imApiUrl ?? '')?.host != 'api.sfhkh.com' ||
      Uri.parse(AppEnvironment.controlPlaneUrl).host != 'api.sfhkh.com') {
    throw StateError('Explicit test03 acceptance session and marker required');
  }
  final startup = MobileStartupDiagnostics.install();
  PaintingBinding.instance.imageCache
    ..maximumSize = 120
    ..maximumSizeBytes = 48 * 1024 * 1024;
  var checkpointReached = false;
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
              if (checkpointReached) return;
              final selfId =
                  await store.readCurrentMemberId(session!.userId) ??
                  session.userId;
              final matches = events
                  .where((event) => event.type == 'message.created')
                  .map(
                    (event) => ImMessage.fromJson(
                      (jsonDecode(event.payloadJson) as Map)
                          .cast<String, Object?>(),
                    ),
                  )
                  .where(
                    (message) =>
                        (conversationId.isEmpty ||
                            message.conversationId == conversationId) &&
                        (message.content == marker ||
                            (requireSelfMention &&
                                message.content.endsWith(' $marker'))) &&
                        (!requireSelfMention ||
                            message.mentions.any(
                              (mention) => mention.mentionedMemberId == selfId,
                            )),
                  )
                  .toList();
              if (matches.length != 1) return;
              final persisted = await store.readMessages(
                session.userId,
                matches.single.conversationId,
              );
              if (persisted.where((m) => m.id == matches.single.id).length !=
                  1) {
                throw StateError('Expected committed test message missing');
              }
              final mentionsSelf = persisted
                  .singleWhere((m) => m.id == matches.single.id)
                  .mentions
                  .any((mention) => mention.mentionedMemberId == selfId);
              final conversation = (await store.readBootstrap(session.userId))!
                  .conversations
                  .singleWhere(
                    (value) => value.id == matches.single.conversationId,
                  );
              if (requireSelfMention &&
                  (!mentionsSelf || !conversation.isGroup)) {
                throw StateError('Expected committed group mention missing');
              }
              checkpointReached = true;
              debugPrint(
                'AI_UAT_IM_CHECKPOINT ${jsonEncode({'stage': 'committed_before_ack', 'eventSequence': sequence, 'messageSequence': matches.single.sequence, 'appliedCursor': await store.lastEventSequence(session.userId, session.syncDeviceId), 'ackedCursor': await store.lastAckedEventSequence(session.userId, session.syncDeviceId), 'copies': 1, 'conversationType': conversation.type, 'mentionsSelf': mentionsSelf})}',
              );
              await Completer<void>().future;
            },
          );
        }),
      ],
      child: const HexingMobileApp(),
    ),
  );
  startup?.mark(MobileStartupStage.runAppReturned);
}
