import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/domain/collaboration_models.dart';

/// Only for a failed *local transaction*. Network failures already belong to
/// the durable IM Outbox. These drafts must never be presented as saved/sent.
final unstoredChatDraftsProvider =
    NotifierProvider<UnstoredChatDrafts, Map<String, List<UnstoredChatDraft>>>(
      UnstoredChatDrafts.new,
    );

class UnstoredChatDraft {
  UnstoredChatDraft({
    required this.content,
    required List<String> mentionedMemberIds,
    required this.mentionAll,
    required this.replyTo,
  }) : clientMessageId = const Uuid().v4(),
       mentionedMemberIds = List.unmodifiable(mentionedMemberIds);

  final String clientMessageId;
  final String content;
  final List<String> mentionedMemberIds;
  final bool mentionAll;
  final ImMessageReply? replyTo;
}

class UnstoredChatDrafts
    extends Notifier<Map<String, List<UnstoredChatDraft>>> {
  int generation = 0;

  @override
  Map<String, List<UnstoredChatDraft>> build() {
    ref.watch(collaborationAccountScopeProvider);
    generation++;
    return const {};
  }

  bool isCurrent(int expectedGeneration) =>
      ref.mounted && generation == expectedGeneration;

  void retain(
    String conversationId,
    UnstoredChatDraft draft,
    int expectedGeneration,
  ) {
    if (!isCurrent(expectedGeneration)) return;
    final items = state[conversationId] ?? const <UnstoredChatDraft>[];
    if (items.any((item) => item.clientMessageId == draft.clientMessageId)) {
      return;
    }
    state = {
      ...state,
      conversationId: List.unmodifiable([...items, draft]),
    };
  }

  void remove(
    String conversationId,
    UnstoredChatDraft draft,
    int expectedGeneration,
  ) {
    if (!isCurrent(expectedGeneration)) return;
    final items = state[conversationId];
    if (items == null) return;
    final remaining = items
        .where((item) => item.clientMessageId != draft.clientMessageId)
        .toList();
    state = {...state, conversationId: List.unmodifiable(remaining)};
  }
}
