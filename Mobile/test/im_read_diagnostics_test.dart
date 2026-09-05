import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/im_read_diagnostics.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';

void main() {
  const conversation = ImConversation(
    id: 'private-conversation-id',
    type: 'group',
    title: 'private-title',
    preview: 'private-body',
    unreadCount: 1,
    lastMessageSequence: 5,
    lastReadSequence: 4,
    updatedAt: null,
  );
  test(
    'opt-in diagnostics whitelist cursor data and deduplicate snapshots',
    () {
      final lines = <String>[];
      final diagnostics = ImReadDiagnostics(enabled: true, sink: lines.add);
      diagnostics.snapshot('bootstrap', 200, [conversation]);
      diagnostics.snapshot('bootstrap', 200, [conversation]);
      diagnostics.action('visible_read_request', conversation.id, sequence: 5);
      diagnostics.events(
        [
          ImSyncEvent(
            sequence: 9,
            id: 'private-event-id',
            type: 'conversation.read',
            createdAt: null,
            payloadJson: jsonEncode({
              'conversationId': conversation.id,
              'readerId': 'private-member-id',
              'sequence': 5,
              'token': 'secret-token',
              'attachment': 'secret-attachment',
            }),
          ),
        ],
        'private-member-id',
        'private-account-id',
      );
      expect(lines, hasLength(3));
      expect(lines.first, contains('"read":4,"unread":1'));
      expect(lines.last, contains('"isSelf":true'));
      expect(lines.join(), isNot(contains('private-')));
      expect(lines.join(), isNot(contains('secret-')));
    },
  );

  test('disabled diagnostics emit nothing including malformed events', () {
    final lines = <String>[];
    final diagnostics = ImReadDiagnostics(enabled: false, sink: lines.add);
    diagnostics.snapshot('bootstrap', 200, [conversation]);
    diagnostics.action('visible_read_request', conversation.id, sequence: 5);
    diagnostics.events(
      [
        const ImSyncEvent(
          sequence: 1,
          id: '1',
          type: 'conversation.read',
          createdAt: null,
          payloadJson: 'invalid',
        ),
      ],
      'self',
      'account',
    );
    expect(lines, isEmpty);
  });
}
