import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../../shared/widgets/page_states.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/domain/collaboration_models.dart';
import 'group_management_page.dart';

class ConversationDetailPage extends ConsumerStatefulWidget {
  const ConversationDetailPage({
    super.key,
    required this.conversation,
    required this.currentMember,
    this.onOpenResource,
  });

  final ImConversation conversation;
  final ImMember currentMember;
  final ValueChanged<int>? onOpenResource;

  @override
  ConsumerState<ConversationDetailPage> createState() =>
      _ConversationDetailPageState();
}

class _ConversationDetailPageState
    extends ConsumerState<ConversationDetailPage> {
  late bool _pinned;
  late bool _muted;
  bool _busy = false;

  ImConversation get conversation => widget.conversation;

  @override
  void initState() {
    super.initState();
    _pinned = conversation.isPinned;
    _muted = conversation.isMuted;
  }

  void _openResource(int tab, String fallbackLocation) {
    final callback = widget.onOpenResource;
    if (callback != null) {
      callback(tab);
      return;
    }
    context.go(fallbackLocation);
  }

  Future<void> _refresh() async {
    final repository = ref.read(imRepositoryProvider);
    await repository.refreshConversationMembers(conversation.id);
    ref.invalidate(conversationMembersProvider(conversation.id));
    if (conversation.isGroup) {
      await repository.refreshGroupProfile(conversation.id);
      ref.invalidate(groupProfileProvider(conversation.id));
      ref.invalidate(groupManagersProvider(conversation.id));
    }
  }

  Future<bool> _run(String failure, Future<void> Function() action) async {
    if (_busy) return false;
    setState(() => _busy = true);
    try {
      await action();
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$failure：$error')));
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _togglePreference({required bool pinned}) async {
    final nextValue = !(pinned ? _pinned : _muted);
    final success = await _run('会话设置更新失败', () async {
      await ref
          .read(imRepositoryProvider)
          .updateConversationPreference(
            conversation.id,
            pinned: pinned ? nextValue : null,
            muted: pinned ? null : nextValue,
          );
      ref.invalidate(imBootstrapProvider);
    });
    if (success && mounted) {
      setState(() {
        if (pinned) {
          _pinned = nextValue;
        } else {
          _muted = nextValue;
        }
      });
    }
  }

  Future<void> _clearConversation() async {
    final confirmed = await _confirm(
      title: '清空聊天记录',
      content: '仅清空当前设备和当前账号的聊天记录。',
      action: '清空',
      destructive: true,
    );
    if (!confirmed) return;
    final success = await _run('聊天记录清空失败', () async {
      await ref.read(imRepositoryProvider).clearConversation(conversation.id);
      ref.invalidate(conversationMessagesProvider(conversation.id));
    });
    if (success && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('聊天记录已清空')));
    }
  }

  Future<void> _deleteDirectConversation() async {
    if (!conversation.isDirect) return;
    final confirmed = await _confirm(
      title: '删除单聊',
      content: '删除后会话将从消息列表移除，再次联系对方时会重新创建单聊。',
      action: '删除',
      destructive: true,
    );
    if (!confirmed) return;
    final success = await _run('删除单聊失败', () async {
      await ref
          .read(imRepositoryProvider)
          .deleteDirectConversation(conversation.id);
      ref.invalidate(imBootstrapProvider);
    });
    if (success && mounted) context.go('/messages');
  }

  Future<void> _editGroupText({
    required String title,
    required String field,
    required String value,
    required int maxLength,
    int maxLines = 1,
  }) async {
    final controller = TextEditingController(text: value);
    final nextValue = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: maxLength,
          maxLines: maxLines,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    await disposeRouteTextController(controller);
    if (nextValue == null || !mounted) return;
    await _run('$title失败', () async {
      await ref.read(imRepositoryProvider).updateGroupProfile(conversation.id, {
        field: nextValue,
      });
      ref.invalidate(groupProfileProvider(conversation.id));
      ref.invalidate(imBootstrapProvider);
    });
  }

  Future<void> _updateGroupSwitch(String field, bool enabled) async {
    await _run('群权限更新失败', () async {
      await ref.read(imRepositoryProvider).updateGroupProfile(conversation.id, {
        field: enabled,
      });
      ref.invalidate(groupProfileProvider(conversation.id));
    });
  }

  Future<void> _addMembers(List<ImMember> members) async {
    final bootstrap = ref.read(imBootstrapProvider).value;
    if (bootstrap == null) return;
    final existingIds = members.map((item) => item.id).toSet();
    final candidates = bootstrap.contacts
        .where((item) => !existingIds.contains(item.id))
        .toList();
    final selected = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MemberPickerSheet(title: '添加群成员', members: candidates),
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    await _run('添加成员失败', () async {
      await ref
          .read(imRepositoryProvider)
          .addGroupMembers(conversation.id, selected);
      ref.invalidate(conversationMembersProvider(conversation.id));
    });
  }

  Future<void> _openMemberDirectory({
    required Set<String> managerIds,
    required String? ownerId,
    required bool isOwner,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _GroupMemberDirectorySheet(
        conversationId: conversation.id,
        currentMemberId: widget.currentMember.id,
        managerIds: managerIds,
        ownerId: ownerId,
        canManageMembers: isOwner,
        onManageMember: (member) {
          Navigator.pop(context);
          _manageMember(
            member: member,
            isManager: managerIds.contains(member.id),
          );
        },
      ),
    );
  }

  Future<void> _manageMember({
    required ImMember member,
    required bool isManager,
  }) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.admin_panel_settings_outlined),
              title: Text(isManager ? '取消管理员' : '设为管理员'),
              onTap: () => Navigator.pop(context, 'role'),
            ),
            ListTile(
              leading: const Icon(Icons.volume_off_outlined),
              title: const Text('禁言 24 小时'),
              onTap: () => Navigator.pop(context, 'mute'),
            ),
            ListTile(
              leading: const Icon(Icons.swap_horiz_rounded),
              title: const Text('转让群主'),
              onTap: () => Navigator.pop(context, 'owner'),
            ),
            ListTile(
              leading: const Icon(
                Icons.person_remove_outlined,
                color: AppColors.error,
              ),
              title: const Text(
                '移出群聊',
                style: TextStyle(color: AppColors.error),
              ),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'mute') {
      await _run('成员禁言失败', () async {
        await ref
            .read(imRepositoryProvider)
            .updateGroupMemberMute(
              conversation.id,
              member.id,
              DateTime.now().toUtc().add(const Duration(hours: 24)),
            );
      });
      return;
    }
    if (action == 'role') {
      await _run('成员角色更新失败', () async {
        await ref
            .read(imRepositoryProvider)
            .updateGroupMemberRole(
              conversation.id,
              member.id,
              isManager ? 'member' : 'admin',
            );
        ref.invalidate(groupManagersProvider(conversation.id));
      });
      return;
    }
    final confirmed = await _confirm(
      title: action == 'owner' ? '转让群主' : '移出群聊',
      content: action == 'owner'
          ? '确认将群主转让给 ${member.displayName}？'
          : '确认将 ${member.displayName} 移出群聊？',
      action: action == 'owner' ? '转让' : '移出',
      destructive: action != 'owner',
    );
    if (!confirmed) return;
    await _run(action == 'owner' ? '群主转让失败' : '移出成员失败', () async {
      final repository = ref.read(imRepositoryProvider);
      if (action == 'owner') {
        await repository.transferGroupOwner(conversation.id, member.id);
      } else {
        await repository.removeGroupMember(conversation.id, member.id);
        ref.invalidate(conversationMembersProvider(conversation.id));
      }
      ref.invalidate(groupManagersProvider(conversation.id));
    });
  }

  Future<void> _leaveOrDissolve(bool dissolve) async {
    final confirmed = await _confirm(
      title: dissolve ? '解散群聊' : '退出群聊',
      content: dissolve ? '群聊和群成员关系将被解除。' : '退出后将不再接收该群消息。',
      action: dissolve ? '解散' : '退出',
      destructive: true,
    );
    if (!confirmed) return;
    final success = await _run(dissolve ? '解散群聊失败' : '退出群聊失败', () async {
      final repository = ref.read(imRepositoryProvider);
      if (dissolve) {
        await repository.dissolveGroup(conversation.id);
      } else {
        await repository.leaveGroup(conversation.id);
      }
      ref.invalidate(imBootstrapProvider);
    });
    if (success && mounted) context.go('/messages');
  }

  Future<void> _copyGroup() async {
    if (!conversation.isGroup) return;
    ImConversation? copied;
    final success = await _run('复制群聊失败', () async {
      copied = await ref.read(imRepositoryProvider).copyGroup(conversation.id);
      ref.invalidate(imBootstrapProvider);
    });
    if (!success || !mounted || copied == null) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('群聊已复制')));
    context.pushReplacement('/chat/${copied!.id}');
  }

  Future<void> _startGroup(ImMember member) async {
    final bootstrap = ref.read(imBootstrapProvider).value;
    if (bootstrap == null || !bootstrap.permissions.createGroup) return;
    final draft = await showModalBottomSheet<_GroupDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) =>
          _CreateGroupSheet(fixedMember: member, contacts: bootstrap.contacts),
    );
    if (draft == null || !mounted) return;
    await _run('群聊创建失败', () async {
      final group = await ref
          .read(imRepositoryProvider)
          .createGroup(draft.title, draft.memberIds);
      ref.invalidate(imBootstrapProvider);
      if (mounted) context.pushReplacement('/chat/${group.id}');
    });
  }

  Future<bool> _confirm({
    required String title,
    required String content,
    required String action,
    bool destructive = false,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                style: destructive
                    ? FilledButton.styleFrom(backgroundColor: AppColors.error)
                    : null,
                onPressed: () => Navigator.pop(context, true),
                child: Text(action),
              ),
            ],
          ),
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final members = ref.watch(conversationMembersProvider(conversation.id));
    final profile = conversation.isGroup
        ? ref.watch(groupProfileProvider(conversation.id)).value
        : null;
    final managers = conversation.isGroup
        ? ref.watch(groupManagersProvider(conversation.id)).value ??
              const <ImMember>[]
        : const <ImMember>[];
    final bootstrap = ref.watch(imBootstrapProvider).value;
    final oa = ref.watch(oaBootstrapProvider).value;
    final conversationMessages =
        ref.watch(conversationMessagesProvider(conversation.id)).value ??
        const <ImMessage>[];
    final sharedFileCount = conversationMessages
        .where(
          (item) =>
              item.kind == 'file' || item.attachmentName.trim().isNotEmpty,
        )
        .length;
    final sharedTodos = (oa?.todos ?? const <OaTodo>[])
        .where(
          (item) =>
              item.conversationId == conversation.id &&
              item.status != 'completed' &&
              item.status != 'canceled',
        )
        .toList(growable: false);
    final relatedApprovals =
        (oa?.approvalRequests ?? const <OaApprovalRequest>[])
            .where(
              (item) =>
                  item.conversationId == conversation.id &&
                  item.status == 'submitted' &&
                  item.requesterId != widget.currentMember.id,
            )
            .toList(growable: false);
    final managerIds = managers.map((item) => item.id).toSet();
    final ownerId = managers
        .where((item) => item.groupRole.toLowerCase() == 'owner')
        .firstOrNull
        ?.id;
    final canManage = managerIds.contains(widget.currentMember.id);
    final isOwner = ownerId == widget.currentMember.id;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(title: Text(conversation.isGroup ? '群聊详情' : '个人资料')),
      body: Stack(
        children: [
          members.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => EmptyState(
              icon: Icons.cloud_off_outlined,
              title: '详情加载失败',
              description: error.toString(),
              onRetry: () =>
                  ref.invalidate(conversationMembersProvider(conversation.id)),
            ),
            data: (items) => RefreshIndicator(
              onRefresh: _refresh,
              child: conversation.isGroup
                  ? _GroupDetail(
                      conversation: conversation,
                      members: items,
                      onlineMemberCount: items
                          .where((member) => member.isOnline)
                          .length,
                      profile: profile,
                      currentMember: widget.currentMember,
                      managerIds: managerIds,
                      ownerId: ownerId,
                      canManage: canManage,
                      isOwner: isOwner,
                      pinned: _pinned,
                      muted: _muted,
                      onAddMembers: () => _addMembers(items),
                      onViewAllMembers: () => _openMemberDirectory(
                        managerIds: managerIds,
                        ownerId: ownerId,
                        isOwner: isOwner,
                      ),
                      onManageMember: (member) => _manageMember(
                        member: member,
                        isManager: managerIds.contains(member.id),
                      ),
                      onEditName: () => _editGroupText(
                        title: '修改群名称',
                        field: 'title',
                        value: profile?.title ?? conversation.title,
                        maxLength: 80,
                      ),
                      onEditNotice: () => _editGroupText(
                        title: '编辑群公告',
                        field: 'notice',
                        value: profile?.notice ?? '',
                        maxLength: 500,
                        maxLines: 6,
                      ),
                      onOpenManagement: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => GroupManagementPage(
                            conversationId: conversation.id,
                          ),
                        ),
                      ),
                      onCopyGroup: _copyGroup,
                      relatedApprovalCount: relatedApprovals.length,
                      onOpenApprovals: () => context.go('/todos'),
                      onGroupSwitch: _updateGroupSwitch,
                      onTogglePinned: () => _togglePreference(pinned: true),
                      onToggleMuted: () => _togglePreference(pinned: false),
                      onClear: _clearConversation,
                      onLeave: () => _leaveOrDissolve(false),
                      onDissolve: () => _leaveOrDissolve(true),
                    )
                  : _DirectDetail(
                      member: items
                          .where((item) => item.id != widget.currentMember.id)
                          .firstOrNull,
                      fallbackTitle: conversation.title,
                      pinned: _pinned,
                      muted: _muted,
                      canCreateGroup:
                          bootstrap?.permissions.createGroup == true,
                      sharedFileCount: sharedFileCount,
                      relatedApprovalCount: relatedApprovals.length,
                      sharedTodoCount: sharedTodos.length,
                      onOpenFiles: () => _openResource(
                        1,
                        '/chat/${conversation.id}?tab=files',
                      ),
                      onOpenApprovals: () => context.go('/todos'),
                      onOpenTodos: () => _openResource(
                        2,
                        '/chat/${conversation.id}?tab=tasks',
                      ),
                      onStartGroup: _startGroup,
                      onTogglePinned: () => _togglePreference(pinned: true),
                      onToggleMuted: () => _togglePreference(pinned: false),
                      onClear: _clearConversation,
                      onDelete: _deleteDirectConversation,
                    ),
            ),
          ),
          if (_busy)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x22000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

class _DirectDetail extends StatelessWidget {
  const _DirectDetail({
    required this.member,
    required this.fallbackTitle,
    required this.pinned,
    required this.muted,
    required this.canCreateGroup,
    required this.sharedFileCount,
    required this.relatedApprovalCount,
    required this.sharedTodoCount,
    required this.onOpenFiles,
    required this.onOpenApprovals,
    required this.onOpenTodos,
    required this.onStartGroup,
    required this.onTogglePinned,
    required this.onToggleMuted,
    required this.onClear,
    required this.onDelete,
  });

  final ImMember? member;
  final String fallbackTitle;
  final bool pinned;
  final bool muted;
  final bool canCreateGroup;
  final int sharedFileCount;
  final int relatedApprovalCount;
  final int sharedTodoCount;
  final VoidCallback onOpenFiles;
  final VoidCallback onOpenApprovals;
  final VoidCallback onOpenTodos;
  final ValueChanged<ImMember> onStartGroup;
  final VoidCallback onTogglePinned;
  final VoidCallback onToggleMuted;
  final VoidCallback onClear;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final displayName = member?.displayName ?? fallbackTitle;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 12, bottom: 24),
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
          child: Row(
            children: [
              InitialAvatar(
                name: displayName,
                radius: 24,
                online: member?.isOnline == true,
                avatarDataUrl: member?.avatarDataUrl ?? '',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (member?.isOrganizationManager == true) ...[
                          const SizedBox(width: 8),
                          const _ManagerTag(label: '负责人'),
                        ],
                      ],
                    ),
                    if (member != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        _memberPresenceLabel(member!),
                        style: TextStyle(
                          fontSize: 13,
                          color: member!.isOnline
                              ? const Color(0xFF0A9F64)
                              : AppColors.secondaryText,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _InfoSection(
          rows: [
            _InfoRow(label: '账号', value: member?.username ?? '-'),
            _InfoRow(label: '部门', value: member?.departmentName ?? '-'),
          ],
        ),
        if (canCreateGroup && member != null) ...[
          const SizedBox(height: 12),
          _ActionSection(
            children: [
              _ActionRow(
                icon: Icons.group_add_outlined,
                title: '发起群聊',
                onTap: () => onStartGroup(member!),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        _ActionSection(
          children: [
            _ActionRow(
              icon: Icons.folder_open_outlined,
              title: '共享文件',
              value: sharedFileCount == 0 ? '暂无' : '$sharedFileCount 个',
              onTap: onOpenFiles,
            ),
            _ActionRow(
              icon: Icons.fact_check_outlined,
              title: '关联审批',
              value: relatedApprovalCount == 0
                  ? '暂无'
                  : '$relatedApprovalCount 项',
              onTap: onOpenApprovals,
            ),
            _ActionRow(
              icon: Icons.task_alt_outlined,
              title: '共同任务',
              value: sharedTodoCount == 0 ? '暂无' : '$sharedTodoCount 项',
              onTap: onOpenTodos,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _ConversationSettings(
          pinned: pinned,
          muted: muted,
          onTogglePinned: onTogglePinned,
          onToggleMuted: onToggleMuted,
          onClear: onClear,
        ),
        const SizedBox(height: 12),
        _ActionSection(
          children: [
            _ActionRow(
              icon: Icons.delete_outline_rounded,
              title: '删除单聊',
              danger: true,
              onTap: onDelete,
            ),
          ],
        ),
      ],
    );
  }
}

class _GroupDetail extends StatelessWidget {
  const _GroupDetail({
    required this.conversation,
    required this.members,
    required this.onlineMemberCount,
    required this.profile,
    required this.currentMember,
    required this.managerIds,
    required this.ownerId,
    required this.canManage,
    required this.isOwner,
    required this.pinned,
    required this.muted,
    required this.onAddMembers,
    required this.onViewAllMembers,
    required this.onManageMember,
    required this.onEditName,
    required this.onEditNotice,
    required this.onOpenManagement,
    required this.onCopyGroup,
    required this.relatedApprovalCount,
    required this.onOpenApprovals,
    required this.onGroupSwitch,
    required this.onTogglePinned,
    required this.onToggleMuted,
    required this.onClear,
    required this.onLeave,
    required this.onDissolve,
  });

  final ImConversation conversation;
  final List<ImMember> members;
  final int onlineMemberCount;
  final ImGroupProfile? profile;
  final ImMember currentMember;
  final Set<String> managerIds;
  final String? ownerId;
  final bool canManage;
  final bool isOwner;
  final bool pinned;
  final bool muted;
  final VoidCallback onAddMembers;
  final VoidCallback onViewAllMembers;
  final ValueChanged<ImMember> onManageMember;
  final VoidCallback onEditName;
  final VoidCallback onEditNotice;
  final VoidCallback onOpenManagement;
  final VoidCallback onCopyGroup;
  final int relatedApprovalCount;
  final VoidCallback onOpenApprovals;
  final void Function(String field, bool enabled) onGroupSwitch;
  final VoidCallback onTogglePinned;
  final VoidCallback onToggleMuted;
  final VoidCallback onClear;
  final VoidCallback onLeave;
  final VoidCallback onDissolve;

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.only(top: 12, bottom: 24),
    children: [
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 13),
        child: Row(
          children: [
            const _GroupAvatar(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile?.title.isNotEmpty == true
                        ? profile!.title
                        : conversation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${members.length} 位成员 · $onlineMemberCount 人在线',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
            if (canManage)
              IconButton(
                tooltip: '修改群名称',
                onPressed: onEditName,
                icon: const Icon(Icons.edit_outlined),
              ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      Container(
        color: Colors.white,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '群成员（${members.length}）',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onViewAllMembers,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('查看全部'),
                ),
                if (canManage)
                  IconButton(
                    tooltip: '添加成员',
                    onPressed: onAddMembers,
                    icon: const Icon(Icons.person_add_alt_1_outlined),
                  ),
              ],
            ),
            const SizedBox(height: 5),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 5,
                mainAxisExtent: 74,
                crossAxisSpacing: 6,
              ),
              itemCount: members.length > 10 ? 10 : members.length,
              itemBuilder: (context, index) {
                final member = members[index];
                final canOperate =
                    isOwner &&
                    member.id != currentMember.id &&
                    member.id != ownerId;
                return InkWell(
                  onTap: canOperate ? () => onManageMember(member) : null,
                  borderRadius: BorderRadius.circular(6),
                  child: Column(
                    children: [
                      InitialAvatar(
                        name: member.displayName,
                        radius: 20,
                        online: member.isOnline,
                        avatarDataUrl: member.avatarDataUrl,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        member.id == currentMember.id
                            ? '我'
                            : member.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (member.id == ownerId)
                        const _MemberRoleLabel(label: '群主')
                      else if (managerIds.contains(member.id))
                        const _MemberRoleLabel(label: '管理员'),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),
      _ActionSection(
        children: [
          _ActionRow(
            icon: Icons.campaign_outlined,
            title: '群公告',
            value: profile?.notice.trim().isEmpty == false
                ? profile!.notice
                : '暂无公告',
            onTap: canManage ? onEditNotice : null,
          ),
          if (profile?.groupNo.isNotEmpty == true)
            _ActionRow(
              icon: Icons.tag_rounded,
              title: '群号',
              value: profile!.groupNo,
            ),
          if (canManage)
            _ActionRow(
              icon: Icons.manage_accounts_outlined,
              title: '群管理',
              value: '禁言、入群审核、操作记录',
              onTap: onOpenManagement,
            ),
          if (canManage)
            _ActionRow(
              icon: Icons.copy_all_outlined,
              title: '复制群聊',
              onTap: onCopyGroup,
            ),
          _ActionRow(
            icon: Icons.fact_check_outlined,
            title: '群内审批',
            value: relatedApprovalCount == 0 ? '暂无' : '$relatedApprovalCount 项',
            onTap: onOpenApprovals,
          ),
        ],
      ),
      if (canManage && profile != null) ...[
        const SizedBox(height: 12),
        _SwitchSection(
          title: '群权限',
          items: [
            _SwitchItem(
              label: '入群需审核',
              value: profile!.reviewEnabled,
              onChanged: (value) => onGroupSwitch('reviewEnabled', value),
            ),
            _SwitchItem(
              label: '成员可查看群成员',
              value: profile!.viewMembersEnabled,
              onChanged: (value) => onGroupSwitch('viewMembersEnabled', value),
            ),
            _SwitchItem(
              label: '允许提及成员',
              value: profile!.atEnabled,
              onChanged: (value) => onGroupSwitch('atEnabled', value),
            ),
            _SwitchItem(
              label: '显示成员身份',
              value: profile!.identityEnabled,
              onChanged: (value) => onGroupSwitch('identityEnabled', value),
            ),
            _SwitchItem(
              label: '允许截图',
              value: profile!.screenshotEnabled,
              onChanged: (value) => onGroupSwitch('screenshotEnabled', value),
            ),
            _SwitchItem(
              label: '全员禁言',
              value: profile!.muted,
              onChanged: (value) => onGroupSwitch('muted', value),
            ),
          ],
        ),
      ],
      const SizedBox(height: 12),
      _ConversationSettings(
        pinned: pinned,
        muted: muted,
        onTogglePinned: onTogglePinned,
        onToggleMuted: onToggleMuted,
        onClear: onClear,
      ),
      const SizedBox(height: 12),
      _ActionSection(
        children: [
          if (!isOwner)
            _ActionRow(
              icon: Icons.logout_rounded,
              title: '退出群聊',
              danger: true,
              onTap: onLeave,
            ),
          if (isOwner)
            _ActionRow(
              icon: Icons.delete_outline_rounded,
              title: '解散群聊',
              danger: true,
              onTap: onDissolve,
            ),
        ],
      ),
    ],
  );
}

class _ConversationSettings extends StatelessWidget {
  const _ConversationSettings({
    required this.pinned,
    required this.muted,
    required this.onTogglePinned,
    required this.onToggleMuted,
    required this.onClear,
  });

  final bool pinned;
  final bool muted;
  final VoidCallback onTogglePinned;
  final VoidCallback onToggleMuted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      _SwitchSection(
        items: [
          _SwitchItem(
            label: '置顶聊天',
            value: pinned,
            onChanged: (_) => onTogglePinned(),
          ),
          _SwitchItem(
            label: '消息免打扰',
            value: muted,
            onChanged: (_) => onToggleMuted(),
          ),
        ],
      ),
      _ActionSection(
        children: [
          _ActionRow(
            icon: Icons.delete_sweep_outlined,
            title: '清空聊天记录',
            onTap: onClear,
          ),
        ],
      ),
    ],
  );
}

class _SwitchItem {
  const _SwitchItem({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
}

class _SwitchSection extends StatelessWidget {
  const _SwitchSection({this.title, required this.items});

  final String? title;
  final List<_SwitchItem> items;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 4),
            child: Text(
              title!,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        for (final item in items)
          ListTile(
            dense: true,
            minTileHeight: 42,
            title: Text(item.label, style: const TextStyle(fontSize: 13)),
            trailing: CompactSwitch(
              value: item.value,
              onChanged: item.onChanged,
            ),
            onTap: () => item.onChanged(!item.value),
          ),
      ],
    ),
  );
}

class _ActionSection extends StatelessWidget {
  const _ActionSection({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    child: Column(children: children),
  );
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    this.value,
    this.danger = false,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? value;
  final bool danger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    minTileHeight: 48,
    leading: Icon(
      icon,
      size: 21,
      color: danger ? AppColors.error : AppColors.primary,
    ),
    title: Text(
      title,
      style: TextStyle(color: danger ? AppColors.error : AppColors.text),
    ),
    trailing: value == null
        ? onTap == null
              ? null
              : const Icon(Icons.chevron_right_rounded)
        : SizedBox(
            width: 190,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.secondaryText),
                  ),
                ),
                if (onTap != null) const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
    onTap: onTap,
  );
}

class _InfoSection extends StatelessWidget {
  const _InfoSection({required this.rows});

  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) => Container(
    color: Colors.white,
    child: Column(children: rows),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 48),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: AppColors.border)),
    ),
    child: Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 15)),
        const SizedBox(width: 24),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.secondaryText),
          ),
        ),
      ],
    ),
  );
}

class _GroupMemberDirectorySheet extends ConsumerStatefulWidget {
  const _GroupMemberDirectorySheet({
    required this.conversationId,
    required this.currentMemberId,
    required this.managerIds,
    required this.ownerId,
    required this.canManageMembers,
    required this.onManageMember,
  });

  final String conversationId;
  final String currentMemberId;
  final Set<String> managerIds;
  final String? ownerId;
  final bool canManageMembers;
  final ValueChanged<ImMember> onManageMember;

  @override
  ConsumerState<_GroupMemberDirectorySheet> createState() =>
      _GroupMemberDirectorySheetState();
}

class _GroupMemberDirectorySheetState
    extends ConsumerState<_GroupMemberDirectorySheet> {
  static const _pageSize = 50;
  final _searchController = TextEditingController();
  int _page = 1;
  String _keyword = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  ({String conversationId, int page, int pageSize, String keyword}) get _key =>
      (
        conversationId: widget.conversationId,
        page: _page,
        pageSize: _pageSize,
        keyword: _keyword,
      );

  void _search() {
    setState(() {
      _keyword = _searchController.text.trim();
      _page = 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(conversationMemberPageProvider(_key));
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .88,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 10, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '全部群成员',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
            child: TextField(
              controller: _searchController,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: '搜索姓名或账号',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: IconButton(
                  tooltip: '搜索',
                  onPressed: _search,
                  icon: const Icon(Icons.arrow_forward_rounded, size: 20),
                ),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: value.when(
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (error, _) => EmptyState(
                icon: Icons.cloud_off_outlined,
                title: '群成员加载失败',
                description: error.toString(),
                onRetry: () =>
                    ref.invalidate(conversationMemberPageProvider(_key)),
              ),
              data: (result) => result.items.isEmpty
                  ? const EmptyState(
                      icon: Icons.group_off_outlined,
                      title: '没有匹配的群成员',
                    )
                  : ListView.separated(
                      itemCount: result.items.length,
                      separatorBuilder: (_, _) =>
                          const Divider(height: 1, indent: 62),
                      itemBuilder: (context, index) {
                        final member = result.items[index];
                        final isOwner = member.id == widget.ownerId;
                        final isManager = widget.managerIds.contains(member.id);
                        final canOperate =
                            widget.canManageMembers &&
                            member.id != widget.currentMemberId &&
                            !isOwner;
                        return ListTile(
                          dense: true,
                          leading: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              InitialAvatar(
                                name: member.displayName,
                                radius: 18,
                                avatarDataUrl: member.avatarDataUrl,
                              ),
                              Positioned(
                                right: -1,
                                bottom: -1,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: member.isOnline
                                        ? const Color(0xFF22B573)
                                        : const Color(0xFFB8C0CC),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: Colors.white,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          title: Text(
                            member.id == widget.currentMemberId
                                ? '${member.displayName}（我）'
                                : member.displayName,
                            style: const TextStyle(fontSize: 13),
                          ),
                          subtitle: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                [
                                  member.departmentName,
                                  member.username,
                                ].where((item) => item.isNotEmpty).join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 10.5),
                              ),
                              const SizedBox(height: 1),
                              Text(
                                _memberPresenceLabel(member),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: member.isOnline
                                      ? const Color(0xFF0A9F64)
                                      : AppColors.secondaryText,
                                ),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (isOwner)
                                const _MemberRoleLabel(label: '群主')
                              else if (isManager)
                                const _MemberRoleLabel(label: '管理员'),
                              if (canOperate)
                                const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                          onTap: canOperate
                              ? () => widget.onManageMember(member)
                              : null,
                        );
                      },
                    ),
            ),
          ),
          value.maybeWhen(
            data: (result) {
              final totalPages = result.total == 0
                  ? 1
                  : (result.total / _pageSize).ceil();
              return SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                  child: Row(
                    children: [
                      Text(
                        '共 ${result.total} 人',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.secondaryText,
                        ),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: '上一页',
                        onPressed: _page > 1
                            ? () => setState(() => _page--)
                            : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Text('$_page / $totalPages'),
                      IconButton(
                        tooltip: '下一页',
                        onPressed: _page < totalPages
                            ? () => setState(() => _page++)
                            : null,
                        icon: const Icon(Icons.chevron_right_rounded),
                      ),
                    ],
                  ),
                ),
              );
            },
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _MemberPickerSheet extends StatefulWidget {
  const _MemberPickerSheet({required this.title, required this.members});

  final String title;
  final List<ImMember> members;

  @override
  State<_MemberPickerSheet> createState() => _MemberPickerSheetState();
}

class _MemberPickerSheetState extends State<_MemberPickerSheet> {
  final Set<String> _selected = {};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final query = _query.toLowerCase();
    final members = widget.members
        .where(
          (item) =>
              query.isEmpty ||
              item.displayName.toLowerCase().contains(query) ||
              item.username.toLowerCase().contains(query) ||
              item.departmentName.toLowerCase().contains(query),
        )
        .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                autofocus: true,
                onChanged: (value) => setState(() => _query = value.trim()),
                decoration: const InputDecoration(
                  hintText: '搜索姓名、部门或账号',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            Expanded(
              child: members.isEmpty
                  ? const EmptyState(
                      icon: Icons.group_off_outlined,
                      title: '没有可选成员',
                    )
                  : ListView.builder(
                      itemCount: members.length,
                      itemBuilder: (context, index) {
                        final member = members[index];
                        return CheckboxListTile(
                          value: _selected.contains(member.id),
                          secondary: InitialAvatar(
                            name: member.displayName,
                            radius: 20,
                            avatarDataUrl: member.avatarDataUrl,
                          ),
                          title: Text(member.displayName),
                          subtitle: Text(
                            [
                              member.departmentName,
                              member.username,
                            ].where((item) => item.isNotEmpty).join(' · '),
                          ),
                          onChanged: (selected) => setState(() {
                            if (selected == true) {
                              _selected.add(member.id);
                            } else {
                              _selected.remove(member.id);
                            }
                          }),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _selected.isEmpty
                      ? null
                      : () => Navigator.pop(context, _selected.toList()),
                  child: Text('确定（${_selected.length}）'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

final class _GroupDraft {
  const _GroupDraft({required this.title, required this.memberIds});

  final String title;
  final List<String> memberIds;
}

class _CreateGroupSheet extends StatefulWidget {
  const _CreateGroupSheet({required this.fixedMember, required this.contacts});

  final ImMember fixedMember;
  final List<ImMember> contacts;

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final TextEditingController _title = TextEditingController();
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _selected.add(widget.fixedMember.id);
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final contacts = widget.contacts
        .where((item) => item.id != widget.fixedMember.id)
        .toList();
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            const Text(
              '发起群聊',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _title,
                maxLength: 80,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: '群名称',
                  counterText: '',
                ),
              ),
            ),
            ListTile(
              leading: InitialAvatar(
                name: widget.fixedMember.displayName,
                radius: 20,
                avatarDataUrl: widget.fixedMember.avatarDataUrl,
              ),
              title: Text(widget.fixedMember.displayName),
              trailing: const Icon(
                Icons.check_circle,
                color: AppColors.primary,
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: contacts.length,
                itemBuilder: (context, index) {
                  final member = contacts[index];
                  return CheckboxListTile(
                    value: _selected.contains(member.id),
                    secondary: InitialAvatar(
                      name: member.displayName,
                      radius: 20,
                      avatarDataUrl: member.avatarDataUrl,
                    ),
                    title: Text(member.displayName),
                    subtitle: Text(member.departmentName),
                    onChanged: (selected) => setState(() {
                      if (selected == true) {
                        _selected.add(member.id);
                      } else {
                        _selected.remove(member.id);
                      }
                    }),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _title.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(
                          context,
                          _GroupDraft(
                            title: _title.text.trim(),
                            memberIds: _selected.toList(),
                          ),
                        ),
                  child: Text('创建群聊（${_selected.length + 1}人）'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManagerTag extends StatelessWidget {
  const _ManagerTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF2FF),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      label,
      style: const TextStyle(fontSize: 11, color: AppColors.primary),
    ),
  );
}

String _memberPresenceLabel(ImMember member, {DateTime? now}) {
  if (member.isOnline) return '在线';
  final lastSeenAt = member.lastSeenAt?.toLocal();
  if (lastSeenAt == null) return '离线';

  final current = (now ?? DateTime.now()).toLocal();
  final currentDay = DateTime(current.year, current.month, current.day);
  final lastSeenDay = DateTime(
    lastSeenAt.year,
    lastSeenAt.month,
    lastSeenAt.day,
  );
  final dayDifference = currentDay.difference(lastSeenDay).inDays;
  if (dayDifference == 0) {
    return '最近上线 ${DateFormat('HH:mm').format(lastSeenAt)}';
  }
  if (dayDifference == 1) {
    return '最近上线 昨天 ${DateFormat('HH:mm').format(lastSeenAt)}';
  }
  return '最近上线 ${DateFormat('MM-dd HH:mm').format(lastSeenAt)}';
}

class _MemberRoleLabel extends StatelessWidget {
  const _MemberRoleLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Text(
    label,
    style: const TextStyle(fontSize: 9, color: AppColors.primary),
  );
}

class _GroupAvatar extends StatelessWidget {
  const _GroupAvatar();

  @override
  Widget build(BuildContext context) => Container(
    width: 48,
    height: 48,
    decoration: BoxDecoration(
      color: const Color(0xFFEAF2FF),
      borderRadius: BorderRadius.circular(8),
    ),
    alignment: Alignment.center,
    child: const Icon(Icons.groups_rounded, size: 28, color: AppColors.primary),
  );
}
