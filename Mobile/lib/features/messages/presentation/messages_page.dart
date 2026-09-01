import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../../shared/widgets/page_states.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/domain/collaboration_models.dart';

class MessagesPage extends ConsumerStatefulWidget {
  const MessagesPage({super.key});

  @override
  ConsumerState<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends ConsumerState<MessagesPage> {
  int _tab = 0;
  String _query = '';
  bool _creating = false;

  Future<void> _startConversation(ImBootstrap data) async {
    if (_creating) return;
    final draft = await showModalBottomSheet<_ConversationDraft>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NewConversationSheet(bootstrap: data),
    );
    if (draft == null || !mounted) return;
    setState(() => _creating = true);
    try {
      final repository = ref.read(imRepositoryProvider);
      final conversation = draft.group
          ? await repository.createGroup(draft.title, draft.memberIds)
          : await repository.createDirect(draft.memberIds.single);
      ref.invalidate(imBootstrapProvider);
      if (mounted) context.push('/chat/${conversation.id}');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('发起会话失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _creating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(imBootstrapProvider);
    const tabs = ['全部', '未读', '@我', '群组'];
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            EnterprisePageHeader(
              title: '消息',
              actions: [
                IconButton(
                  tooltip: '我的收藏',
                  onPressed: () => context.push('/message-favorites'),
                  icon: const Icon(Icons.star_outline_rounded, size: 20),
                ),
                if (value.value?.permissions.batchSend == true)
                  IconButton(
                    tooltip: '群发助手',
                    onPressed: () => context.push('/message-assistant'),
                    icon: const Icon(Icons.campaign_outlined, size: 20),
                  ),
                value.value == null
                    ? const SizedBox(width: 48)
                    : IconButton(
                        tooltip: '发起会话',
                        onPressed: _creating
                            ? null
                            : () => _startConversation(value.requireValue),
                        icon: _creating
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.add_circle_outline_rounded,
                                size: 20,
                              ),
                      ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
              child: MobileSearchField(
                hintText: '搜索联系人、群组或消息',
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
            ),
            SizedBox(
              height: 34,
              child: Row(
                children: List.generate(
                  tabs.length,
                  (index) => Expanded(
                    child: InkWell(
                      onTap: () => setState(() => _tab = index),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: _tab == index
                              ? const Border(
                                  bottom: BorderSide(
                                    color: AppColors.primary,
                                    width: 2,
                                  ),
                                )
                              : null,
                        ),
                        child: Text(
                          tabs[index],
                          style: TextStyle(
                            fontSize: 13,
                            color: _tab == index
                                ? AppColors.primary
                                : AppColors.secondaryText,
                            fontWeight: _tab == index
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Material(
                  key: const Key('messages-flat-content'),
                  type: MaterialType.transparency,
                  child: value.when(
                    loading: () => const ModuleLoadingState(label: '正在加载消息'),
                    error: (error, _) => EmptyState(
                      icon: Icons.cloud_off_outlined,
                      title: '消息加载失败',
                      description: error.toString(),
                      onRetry: () => ref.invalidate(imBootstrapProvider),
                    ),
                    data: (data) {
                      final query = _query.toLowerCase();
                      final items = data.conversations.where((item) {
                        if (_tab == 1 && item.unreadCount <= 0) return false;
                        if (_tab == 2 && !item.hasUnreadMention) return false;
                        if (_tab == 3 && !item.isGroup) return false;
                        return imConversationMatchesQuery(
                          item,
                          data.contacts,
                          data.currentMember.id,
                          query,
                        );
                      }).toList();
                      if (items.isEmpty) {
                        return EmptyState(
                          icon: Icons.chat_bubble_outline_rounded,
                          title: query.isEmpty ? '暂无会话' : '没有匹配的会话',
                        );
                      }
                      return RefreshIndicator(
                        onRefresh: () =>
                            ref.refresh(imBootstrapProvider.future),
                        child: ListView.separated(
                          itemCount: items.length,
                          separatorBuilder: (_, _) => const Divider(indent: 62),
                          itemBuilder: (context, index) => _ConversationTile(
                            item: items[index],
                            currentMember: data.currentMember,
                            contacts: data.contacts,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _ConversationDraft {
  const _ConversationDraft({
    required this.group,
    required this.title,
    required this.memberIds,
  });

  final bool group;
  final String title;
  final List<String> memberIds;
}

class _NewConversationSheet extends StatefulWidget {
  const _NewConversationSheet({required this.bootstrap});

  final ImBootstrap bootstrap;

  @override
  State<_NewConversationSheet> createState() => _NewConversationSheetState();
}

class _NewConversationSheetState extends State<_NewConversationSheet> {
  final _titleController = TextEditingController();
  final _selectedIds = <String>{};
  bool _group = false;
  String _query = '';

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final contacts = widget.bootstrap.contacts.where((item) {
      if (!_group && !item.canStartDirect) return false;
      return query.isEmpty ||
          item.displayName.toLowerCase().contains(query) ||
          item.username.toLowerCase().contains(query) ||
          item.departmentName.toLowerCase().contains(query);
    }).toList();
    final canSubmitGroup =
        _selectedIds.isNotEmpty && _titleController.text.trim().isNotEmpty;

    return SafeArea(
      child: SizedBox(
        key: const Key('new-conversation-sheet'),
        height: MediaQuery.sizeOf(context).height * .68,
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                '发起会话',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
            if (widget.bootstrap.permissions.createGroup)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<bool>(
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity(
                        horizontal: -2,
                        vertical: -3,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: WidgetStatePropertyAll(Size(0, 36)),
                      padding: WidgetStatePropertyAll(
                        EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      ),
                      iconSize: WidgetStatePropertyAll(18),
                    ),
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.person_outline_rounded),
                        label: Text(
                          '单聊',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.groups_outlined),
                        label: Text(
                          '群聊',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                    selected: {_group},
                    onSelectionChanged: (value) => setState(() {
                      _group = value.single;
                      _selectedIds.clear();
                    }),
                  ),
                ),
              ),
            if (_group)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _titleController,
                    maxLength: 80,
                    style: const TextStyle(fontSize: 14),
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      hintText: '群名称',
                      prefixIcon: Icon(Icons.edit_outlined, size: 18),
                      prefixIconConstraints: BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                      counterText: '',
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: MobileSearchField(
                hintText: '搜索姓名、部门或账号',
                autofocus: true,
                onChanged: (value) => setState(() => _query = value.trim()),
              ),
            ),
            Expanded(
              child: contacts.isEmpty
                  ? const Center(child: Text('没有可选择的联系人'))
                  : ListView.builder(
                      itemCount: contacts.length,
                      itemBuilder: (context, index) {
                        final member = contacts[index];
                        final selected = _selectedIds.contains(member.id);
                        return ListTile(
                          dense: true,
                          minTileHeight: 50,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                          ),
                          leading: InitialAvatar(
                            name: member.displayName,
                            radius: 18,
                            avatarKey: member.avatarKey,
                            avatarDataUrl: member.avatarDataUrl,
                          ),
                          title: Text(
                            member.displayName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            [
                              member.departmentName,
                              member.username,
                            ].where((value) => value.isNotEmpty).join(' · '),
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: _group
                              ? Checkbox(
                                  value: selected,
                                  onChanged: (_) => _toggle(member.id),
                                )
                              : const Icon(
                                  Icons.chevron_right_rounded,
                                  size: 18,
                                ),
                          onTap: _group
                              ? () => _toggle(member.id)
                              : () => Navigator.pop(
                                  context,
                                  _ConversationDraft(
                                    group: false,
                                    title: '',
                                    memberIds: [member.id],
                                  ),
                                ),
                        );
                      },
                    ),
            ),
            if (_group)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: SizedBox(
                  width: double.infinity,
                  height: 38,
                  child: FilledButton.icon(
                    onPressed: canSubmitGroup
                        ? () => Navigator.pop(
                            context,
                            _ConversationDraft(
                              group: true,
                              title: _titleController.text.trim(),
                              memberIds: _selectedIds.toList(),
                            ),
                          )
                        : null,
                    icon: const Icon(Icons.group_add_outlined, size: 18),
                    label: Text(
                      '创建群聊（${_selectedIds.length}）',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _toggle(String memberId) => setState(() {
    if (!_selectedIds.add(memberId)) _selectedIds.remove(memberId);
  });
}

class _ConversationTile extends ConsumerWidget {
  const _ConversationTile({
    required this.item,
    required this.currentMember,
    required this.contacts,
  });

  final ImConversation item;
  final ImMember currentMember;
  final List<ImMember> contacts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = item.isGroup
        ? const <ImMember>[]
        : ref.watch(conversationMembersProvider(item.id)).value ??
              const <ImMember>[];
    final title = imConversationDisplayTitle(
      item,
      members,
      currentMember.id,
      currentDisplayName: currentMember.displayName,
      contacts: contacts,
    );
    final peer = item.isDirect
        ? imDirectConversationPeer(
            members,
            currentMember.id,
            conversation: item,
            contacts: contacts,
          )
        : null;
    return InkWell(
      onTap: () => context.push('/chat/${item.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          children: [
            Semantics(
              label: item.isGroup
                  ? '群聊'
                  : peer?.isOnline == true
                  ? '单聊，对方在线'
                  : '单聊，对方离线',
              child: item.isGroup
                  ? Container(
                      key: ValueKey('message-group-avatar-${item.id}'),
                      width: 36,
                      height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F1FF),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.groups_rounded,
                        size: 20,
                        color: AppColors.primary,
                      ),
                    )
                  : InitialAvatar(
                      key: ValueKey('message-direct-avatar-${item.id}'),
                      name: title,
                      radius: 18,
                      online: peer?.isOnline,
                      avatarKey: peer?.avatarKey ?? '',
                      avatarDataUrl: peer?.avatarDataUrl ?? '',
                      backgroundColor: const Color(0xFFE8F6F2),
                    ),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (item.isGroup) ...[
                        const SizedBox(width: 5),
                        Container(
                          key: ValueKey('group-badge-${item.id}'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF2FF),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: const Text(
                            '群聊',
                            style: TextStyle(
                              fontSize: 9,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  item.updatedAt == null
                      ? ''
                      : DateFormat('HH:mm').format(item.updatedAt!),
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 5),
                if (item.unreadCount > 0)
                  Badge(label: Text('${item.unreadCount}'))
                else
                  const SizedBox(height: 18),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

String imConversationDisplayTitle(
  ImConversation conversation,
  List<ImMember> members,
  String currentMemberId, {
  String currentDisplayName = '',
  List<ImMember> contacts = const <ImMember>[],
}) {
  if (conversation.isGroup) return conversation.title;
  if (!conversation.isDirect) return '不支持的会话';
  final peer = imDirectConversationPeer(
    members,
    currentMemberId,
    conversation: conversation,
    contacts: contacts,
  );
  if (peer != null && peer.displayName.trim().isNotEmpty) {
    return peer.displayName.trim();
  }
  final titleParts = _directConversationTitleParts(conversation.title);
  final normalizedCurrentName = currentDisplayName.trim().toLowerCase();
  final peerParts = normalizedCurrentName.isEmpty
      ? titleParts
      : titleParts
            .where((part) => part.toLowerCase() != normalizedCurrentName)
            .toList(growable: false);
  if (peerParts.length == 1) return peerParts.single;
  return conversation.title;
}

ImMember? imDirectConversationPeer(
  List<ImMember> members,
  String currentMemberId, {
  ImConversation? conversation,
  List<ImMember> contacts = const <ImMember>[],
}) {
  for (final member in members) {
    if (member.id != currentMemberId) return member;
  }
  if (conversation == null || !conversation.isDirect) return null;
  final titleParts = _directConversationTitleParts(conversation.title)
      .map((part) => part.toLowerCase())
      .toSet();
  for (final contact in contacts) {
    if (contact.id == currentMemberId) continue;
    final displayName = contact.displayName.trim().toLowerCase();
    final username = contact.username.trim().toLowerCase();
    if ((displayName.isNotEmpty && titleParts.contains(displayName)) ||
        (username.isNotEmpty && titleParts.contains(username))) {
      return contact;
    }
  }
  return null;
}

List<String> _directConversationTitleParts(String title) => title
    .split(RegExp(r'[、,，]'))
    .map((value) => value.trim())
    .where((value) => value.isNotEmpty)
    .toList(growable: false);

bool imConversationMatchesQuery(
  ImConversation conversation,
  List<ImMember> contacts,
  String currentMemberId,
  String query,
) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return true;

  final searchable = <String>[conversation.title, conversation.preview];
  if (conversation.isDirect) {
    final titleNames = conversation.title
        .split(RegExp(r'[、,，]'))
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    for (final contact in contacts) {
      if (contact.id == currentMemberId) continue;
      final displayName = contact.displayName.trim().toLowerCase();
      if (displayName.isEmpty || !titleNames.contains(displayName)) continue;
      searchable.addAll([
        contact.displayName,
        contact.username,
        contact.departmentName,
      ]);
    }
  }
  return searchable.any((value) => value.toLowerCase().contains(normalized));
}
