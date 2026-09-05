/// Keep the expression index and the message window query identical: SQLite
/// matches expression indexes syntactically, not by algebraic equivalence.
abstract final class ImMessageQuery {
  static const pendingOrder = 'CASE WHEN sequence = 0 THEN 1 ELSE 0 END';
  static const oldestFirst = '$pendingOrder, sequence, created_at';
  static const newestFirst =
      '$pendingOrder DESC, sequence DESC, created_at DESC';
  static const visibleWhere =
      'account_id = ? AND conversation_id = ? AND is_deleted = 0';
  static const windowIndexName = 'ix_im_messages_visible_window';
  static const createWindowIndex =
      '''
    CREATE INDEX IF NOT EXISTS $windowIndexName
    ON im_messages(account_id, conversation_id, $pendingOrder, sequence, created_at)
    WHERE is_deleted = 0
  ''';

  // Receipt projection is account/conversation scoped and uses indexed state
  // lookups. Reuse the exact projection in plan/performance regression tests.
  static const columns = <String>[
    '*',
    '''(sequence > 0 AND (
      EXISTS (SELECT 1 FROM im_sync_state s
        WHERE s.account_id = im_messages.account_id
          AND s.state_key = 'recipient.read.' || im_messages.conversation_id
          AND CAST(s.value AS INTEGER) >= im_messages.sequence)
      OR EXISTS (SELECT 1 FROM im_sync_state s
        WHERE s.account_id = im_messages.account_id
          AND s.state_key = 'message.read.' || im_messages.conversation_id || '.' || im_messages.id
          AND s.value = '1')
    )) AS recipient_read''',
  ];
}
