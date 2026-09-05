/// Cross-client IM rules shared with the Windows implementation contract.
///
/// Keep this file free of UI and transport dependencies so event replay,
/// history reconciliation and other clients can use the same semantics.
abstract final class ImEventSemantics {
  static String canonicalType(String value) => value.trim().toLowerCase();

  static bool isMessageCreated(String value) =>
      canonicalType(value) == 'message.created';

  static bool isConversationRead(String value) =>
      canonicalType(value) == 'conversation.read';

  static bool isCurrentReader({
    required String readerId,
    required String accountId,
    required String currentMemberId,
  }) =>
      readerId.isNotEmpty &&
      (readerId == accountId || readerId == currentMemberId);

  /// Read cursors are monotonic on every device, including events emitted by
  /// another client logged in as the same account.
  static int mergeReadSequence(int current, int incoming) =>
      incoming > current ? incoming : current;

  /// A server message id is authoritative. A sender-scoped client id keeps an
  /// optimistic outbox row and the later server/event echo as one message.
  static String messageDedupeKey({
    required String serverMessageId,
    required String senderId,
    required String clientMessageId,
  }) {
    if (serverMessageId.trim().isNotEmpty) {
      return 'server:${serverMessageId.trim()}';
    }
    if (senderId.trim().isNotEmpty && clientMessageId.trim().isNotEmpty) {
      return 'client:${senderId.trim()}:${clientMessageId.trim()}';
    }
    return '';
  }
}
