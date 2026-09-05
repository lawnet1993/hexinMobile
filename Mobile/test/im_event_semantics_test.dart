import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/im_event_semantics.dart';

void main() {
  test('event names and current-account reads use the shared contract', () {
    expect(ImEventSemantics.isMessageCreated(' Message.Created '), isTrue);
    expect(ImEventSemantics.isConversationRead('Conversation.Read'), isTrue);
    expect(
      ImEventSemantics.isCurrentReader(
        readerId: 'account',
        accountId: 'account',
        currentMemberId: 'member',
      ),
      isTrue,
    );
    expect(ImEventSemantics.mergeReadSequence(18, 12), 18);
    expect(ImEventSemantics.mergeReadSequence(18, 21), 21);
  });

  test('message dedupe prefers server id then sender-scoped client id', () {
    expect(
      ImEventSemantics.messageDedupeKey(
        serverMessageId: 'server-1',
        senderId: 'sender',
        clientMessageId: 'client-1',
      ),
      'server:server-1',
    );
    expect(
      ImEventSemantics.messageDedupeKey(
        serverMessageId: '',
        senderId: 'sender',
        clientMessageId: 'client-1',
      ),
      'client:sender:client-1',
    );
    expect(
      ImEventSemantics.messageDedupeKey(
        serverMessageId: '',
        senderId: '',
        clientMessageId: 'client-1',
      ),
      isEmpty,
    );
  });
}
