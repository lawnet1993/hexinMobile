import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/errors/mobile_error_text.dart';
import '../../../shared/widgets/mobile_bottom_sheets.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../../shared/widgets/page_states.dart';
import '../../../shared/widgets/visible_refresh_scheduler.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/data/im_member_presence.dart';
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
  late final VisibleRefreshScheduler _presenceRefreshScheduler;
  String? _memberSnapshotScope;

  ImConversation get conversation => widget.conversation;

  ({String conversationId, int page, int pageSize, String keyword})
  get _memberPageKey =>
      (conversationId: conversation.id, page: 1, pageSize: 50, keyword: '');

  @override
  void initState() {
    super.initState();
    _pinned = conversation.isPinned;
    _muted = conversation.isMuted;
    _presenceRefreshScheduler = VisibleRefreshScheduler(
      _refreshVisiblePresence,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _presenceRefreshScheduler.setVisible(
      conversation.isGroup &&
          TickerMode.valuesOf(context).enabled &&
          (ModalRoute.of(context)?.isCurrent ?? true),
    );
  }

  @override
  void dispose() {
    _presenceRefreshScheduler.dispose();
    super.dispose();
  }

  Future<void> _refreshVisiblePresence() async {
    if (!mounted || !conversation.isGroup) return;
    final members = conversationMemberPageProvider(_memberPageKey);
    final presence = conversationPresenceProvider(conversation.id);
    if (!ref.read(members).isLoading) ref.invalidate(members);
    if (!ref.read(presence).isLoading) ref.invalidate(presence);
    await Future.wait([ref.read(members.future), ref.read(presence.future)]);
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
    if (conversation.isGroup) {
      await _refreshVisiblePresence();
      await repository.refreshGroupProfile(conversation.id);
      ref.invalidate(groupProfileProvider(conversation.id));
      ref.invalidate(groupManagersProvider(conversation.id));
    } else {
      await repository.refreshConversationMembers(conversation.id);
      ref.invalidate(conversationMembersProvider(conversation.id));
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileActionErrorText(failure, error))),
        );
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
    final nextValue = await showMobileTextInputSheet(
      context,
      title: title,
      initialValue: value,
      maxLength: maxLength,
      maxLines: maxLines,
    );
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
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) => _MemberPickerSheet(title: '添加群成员', members: candidates),
    );
    if (selected == null || selected.isEmpty || !mounted) return;
    await _run('添加成员失败', () async {
      await ref
          .read(imRepositoryProvider)
          .addGroupMembers(conversation.id, selected);
      ref.invalidate(conversationMemberPageProvider(_memberPageKey));
    });
  }

  Future<void> _openMemberDirectory({
    required Set<String> managerIds,
    required String? ownerId,
    required bool isOwner,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
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
    final action = await showMobileChoiceSheet<String>(
      context,
      title: '管理 ${member.displayName}',
      options: [
        MobileSheetOption(
          value: 'role',
          label: isManager ? '取消管理员' : '设为管理员',
          icon: Icons.admin_panel_settings_outlined,
        ),
        const MobileSheetOption(
          value: 'mute',
          label: '禁言 24 小时',
          icon: Icons.volume_off_outlined,
        ),
        const MobileSheetOption(
          value: 'owner',
          label: '转让群主',
          icon: Icons.swap_horiz_rounded,
        ),
        const MobileSheetOption(
          value: 'remove',
          label: '移出群聊',
          icon: Icons.person_remove_outlined,
          destructive: true,
        ),
      ],
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
        ref.invalidate(conversationMemberPageProvider(_memberPageKey));
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
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (_) =>
          _CreateGroupSheet(fixedMember: member, contacts: bootstrap.contacts),
    );
    if (draft == null || !mounted) return;
    await _run('群聊创建失败', () async {
      final group = await ref
          .read(imRepositoryProvider)
          .createGroup(draft.title, draft.memberIds);
      ref.invalidate(imBootstrapProvider);
      if (mounted) {
        context.pushReplacement('/chat/${group.id}', extra: group);
      }
    });
  }

  Future<bool> _confirm({
    required String title,
    required String content,
    required String action,
    bool destructive = false,
  }) async {
    return await showMobileConfirmSheet(
          context,
          title: title,
          message: content,
          confirmLabel: action,
          destructive: destructive,
        ) ??
        false;
  }

  @override
  Widget build(BuildContext context) {
    final groupMemberPage = conversation.isGroup
        ? ref.watch(conversationMemberPageProvider(_memberPageKey))
        : null;
    final AsyncValue<List<ImMember>> members = conversation.isGroup
        ? groupMemberPage!.whenData((page) => page.items)
        : ref.watch(conversationMembersProvider(conversation.id));
    final accountScope = ref.watch(collaborationAccountScopeProvider);
    if (members.hasValue && !members.isLoading && !members.hasError) {
      _memberSnapshotScope = accountScope;
    }
    final keepMemberSnapshot = _memberSnapshotScope == accountScope;
    final memberTotal = groupMemberPage?.value?.total;
    final presenceState = conversation.isGroup
        ? ref.watch(conversationPresenceProvider(conversation.id))
        : null;
    final presence =
        presenceState?.isLoading == false &&
            presenceState?.hasError == false &&
            presenceState?.value?.type == 'group'
        ? presenceState?.value
        : null;
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
    final currentUserRole = profile?.currentUserRole.trim().toLowerCase() ?? '';
    final canManage =
        managerIds.contains(widget.currentMember.id) ||
        const {'owner', 'admin', 'administrator'}.contains(currentUserRole);
    final isOwner =
        ownerId == widget.currentMember.id || currentUserRole == 'owner';

    return Scaffold(
      backgroundColor: const Color(0xFFF5F6F8),
      appBar: AppBar(title: Text(conversation.isGroup ? '群聊详情' : '个人资料')),
      body: Stack(
        children: [
          members.when(
            skipError: keepMemberSnapshot,
            skipLoadingOnRefresh: keepMemberSnapshot,
            skipLoadingOnReload: keepMemberSnapshot,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => EmptyState(
              icon: Icons.cloud_off_outlined,
              title: '详情加载失败',
              description: mobileErrorText(error),
              onRetry: () => conversation.isGroup
                  ? ref.invalidate(
                      conversationMemberPageProvider(_memberPageKey),
                    )
                  : ref.invalidate(
                      conversationMembersProvider(conversation.id),
                    ),
            ),
            data: (items) => RefreshIndicator(
              onRefresh: _refresh,
              child: conversation.isGroup
                  ? _GroupDetail(
                      conversation: conversation,
                      members: items,
                      memberCount: memberTotal ?? items.length,
                      onlineMemberCount: presence?.onlineMemberCount,
                      memberPresenceAvailable:
                          groupMemberPage?.isLoading == false &&
                          groupMemberPage?.hasError == false,
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
              Consumer(
                builder: (context, ref, _) => InitialAvatar(
                  name: displayName,
                  radius: 24,
                  online: watchMemberPresence(
                    ref,
                    member,
                    transportAvailable:
                        ref.watch(imRealtimeAvailabilityProvider) ==
                        ImRealtimeAvailability.available,
                  ).online,
                  avatarKey: member?.avatarKey ?? '',
                  avatarDataUrl: member?.avatarDataUrl ?? '',
                ),
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
                      Consumer(
                        builder: (context, ref, _) {
                          final presence = watchMemberPresence(
                            ref,
                            member,
                            transportAvailable:
                                ref.watch(imRealtimeAvailabilityProvider) ==
                                ImRealtimeAvailability.available,
                          );
                          return Text(
                            _memberPresenceLabel(presence),
                            style: TextStyle(
                              fontSize: 13,
                              color: presence.online == true
                                  ? const Color(0xFF0A9F64)
                                  : AppColors.secondaryText,
                              fontWeight: FontWeight.w500,
                            ),
                          );
                        },
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
    required this.memberCount,
    required this.onlineMemberCount,
    required this.memberPresenceAvailable,
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
  final int memberCount;
  final int? onlineMemberCount;
  final bool memberPresenceAvailable;
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
                  Consumer(
                    builder: (context, ref, _) => Text(
                      ref.watch(imRealtimeAvailabilityProvider) ==
                                  ImRealtimeAvailability.available &&
                              onlineMemberCount != null
                          ? '$memberCount 位成员 · $onlineMemberCount 人在线'
                          : '$memberCount 位成员',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.secondaryText,
                      ),
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
                    '群成员（$memberCount）',
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
                      Consumer(
                        builder: (context, ref, _) => InitialAvatar(
                          name: member.displayName,
                          radius: 20,
                          online: watchMemberPresence(
                            ref,
                            member,
                            transportAvailable:
                                ref.watch(imRealtimeAvailabilityProvider) ==
                                    ImRealtimeAvailability.available &&
                                memberPresenceAvailable,
                          ).online,
                          avatarKey: member.avatarKey,
                          avatarDataUrl: member.avatarDataUrl,
                        ),
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
  // The backend may still match an account identifier, but the mobile member
  // directory deliberately presents people rather than login credentials.
  final _searchController = MobileSearchTextController(searchLabel: '搜索成员');
  late final VisibleRefreshScheduler _presenceRefreshScheduler;
  String? _memberSnapshotScope;
  int _page = 1;
  String _keyword = '';

  @override
  void initState() {
    super.initState();
    _presenceRefreshScheduler = VisibleRefreshScheduler(() async {
      final provider = conversationMemberPageProvider(_key);
      if (!ref.read(provider).isLoading) ref.invalidate(provider);
      await ref.read(provider.future);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _presenceRefreshScheduler.setVisible(
      TickerMode.valuesOf(context).enabled &&
          (ModalRoute.of(context)?.isCurrent ?? true),
    );
  }

  @override
  void dispose() {
    _presenceRefreshScheduler.dispose();
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
    ref.invalidate(conversationMemberPageProvider(_key));
  }

  void _changePage(int page) {
    setState(() => _page = page);
    ref.invalidate(conversationMemberPageProvider(_key));
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(conversationMemberPageProvider(_key));
    final accountScope = ref.watch(collaborationAccountScopeProvider);
    if (value.hasValue && !value.isLoading && !value.hasError) {
      _memberSnapshotScope = accountScope;
    }
    final keepMemberSnapshot = _memberSnapshotScope == accountScope;
    final presenceAvailable =
        ref.watch(imRealtimeAvailabilityProvider) ==
            ImRealtimeAvailability.available &&
        !value.isLoading &&
        !value.hasError;
    return SizedBox(
      key: const Key('group-member-directory-sheet'),
      height: MediaQuery.sizeOf(context).height * .88,
      child: Column(
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '全部群成员',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded, size: 19),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: MobileSearchField(
                    key: const Key('group-member-directory-search'),
                    controller: _searchController,
                    hintText: '搜索成员',
                    onSubmitted: (_) => _search(),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox.square(
                  dimension: 34,
                  child: IconButton.filledTonal(
                    tooltip: '搜索',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    onPressed: _search,
                    icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: value.when(
              skipError: keepMemberSnapshot,
              skipLoadingOnRefresh: keepMemberSnapshot,
              skipLoadingOnReload: keepMemberSnapshot,
              loading: () => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              error: (error, _) => EmptyState(
                icon: Icons.cloud_off_outlined,
                title: '群成员加载失败',
                description: mobileErrorText(error),
                onRetry: () =>
                    ref.invalidate(conversationMemberPageProvider(_key)),
              ),
              data: (result) => result.items.isEmpty
                  ? const EmptyState(
                      icon: Icons.group_off_outlined,
                      title: '没有匹配的群成员',
                    )
                  : ListView.builder(
                      itemCount: result.items.length,
                      itemBuilder: (context, index) {
                        final member = result.items[index];
                        final isOwner = member.id == widget.ownerId;
                        final isManager = widget.managerIds.contains(member.id);
                        final canOperate =
                            widget.canManageMembers &&
                            member.id != widget.currentMemberId &&
                            !isOwner;
                        return Consumer(
                          builder: (context, ref, _) {
                            final presence = watchMemberPresence(
                              ref,
                              member,
                              transportAvailable: presenceAvailable,
                            );
                            return SizedBox(
                              key: ValueKey(
                                'group-member-directory-member-${member.id}',
                              ),
                              height: 54,
                              child: ListTile(
                                dense: true,
                                visualDensity: VisualDensity.compact,
                                minLeadingWidth: 36,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                leading: InitialAvatar(
                                  name: member.displayName,
                                  radius: 18,
                                  online: presence.online,
                                  avatarKey: member.avatarKey,
                                  avatarDataUrl: member.avatarDataUrl,
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
                                    if (member.departmentName.isNotEmpty) ...[
                                      Text(
                                        member.departmentName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 10.5),
                                      ),
                                      const SizedBox(height: 1),
                                    ],
                                    Text(
                                      _memberPresenceLabel(presence),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: presence.online == true
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
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ),
          value.maybeWhen(
            skipError: keepMemberSnapshot,
            skipLoadingOnRefresh: keepMemberSnapshot,
            skipLoadingOnReload: keepMemberSnapshot,
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
                            ? () => _changePage(_page - 1)
                            : null,
                        icon: const Icon(Icons.chevron_left_rounded),
                      ),
                      Text('$_page / $totalPages'),
                      IconButton(
                        tooltip: '下一页',
                        onPressed: _page < totalPages
                            ? () => _changePage(_page + 1)
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
        key: const Key('group-member-picker-sheet'),
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: MobileSearchField(
                key: const Key('group-member-picker-search'),
                hintText: '搜索姓名、部门或账号',
                autofocus: false,
                onChanged: (value) => setState(() => _query = value.trim()),
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
                        return SizedBox(
                          key: ValueKey(
                            'group-member-picker-member-${member.id}',
                          ),
                          height: 50,
                          child: CheckboxListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                            ),
                            value: _selected.contains(member.id),
                            secondary: Consumer(
                              builder: (context, ref, _) => InitialAvatar(
                                name: member.displayName,
                                radius: 17,
                                online: watchMemberPresence(
                                  ref,
                                  member,
                                  transportAvailable:
                                      ref.watch(
                                        imRealtimeAvailabilityProvider,
                                      ) ==
                                      ImRealtimeAvailability.available,
                                ).online,
                                avatarKey: member.avatarKey,
                                avatarDataUrl: member.avatarDataUrl,
                              ),
                            ),
                            title: Text(
                              member.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: member.departmentName.isEmpty
                                ? null
                                : Text(
                                    member.departmentName,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                            onChanged: (selected) => setState(() {
                              if (selected == true) {
                                _selected.add(member.id);
                              } else {
                                _selected.remove(member.id);
                              }
                            }),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(60, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('group-member-picker-submit'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(78, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.pop(context, _selected.toList()),
                    child: Text('确定（${_selected.length}）'),
                  ),
                ],
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
        key: const Key('create-group-sheet'),
        height: MediaQuery.sizeOf(context).height * .72,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '发起群聊',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
              child: SizedBox(
                height: 36,
                child: TextField(
                  key: const Key('create-group-title-input'),
                  controller: _title,
                  maxLength: 80,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: '群名称',
                    counterText: '',
                    isDense: true,
                    filled: true,
                    fillColor: Theme.of(context)
                        .colorScheme
                        .surfaceContainerHighest
                        .withValues(alpha: .6),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    border: const OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    enabledBorder: const OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide.none,
                      borderRadius: BorderRadius.all(Radius.circular(8)),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              height: 50,
              child: ListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                leading: Consumer(
                  builder: (context, ref, _) => InitialAvatar(
                    name: widget.fixedMember.displayName,
                    radius: 17,
                    online: watchMemberPresence(
                      ref,
                      widget.fixedMember,
                      transportAvailable:
                          ref.watch(imRealtimeAvailabilityProvider) ==
                          ImRealtimeAvailability.available,
                    ).online,
                    avatarKey: widget.fixedMember.avatarKey,
                    avatarDataUrl: widget.fixedMember.avatarDataUrl,
                  ),
                ),
                title: Text(
                  widget.fixedMember.displayName,
                  style: const TextStyle(fontSize: 13.5),
                ),
                subtitle: widget.fixedMember.departmentName.isEmpty
                    ? null
                    : Text(
                        widget.fixedMember.departmentName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.secondaryText,
                        ),
                      ),
                trailing: const Icon(
                  Icons.check_circle,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: contacts.length,
                itemBuilder: (context, index) {
                  final member = contacts[index];
                  return SizedBox(
                    key: ValueKey('create-group-member-${member.id}'),
                    height: 50,
                    child: CheckboxListTile(
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                      ),
                      value: _selected.contains(member.id),
                      secondary: Consumer(
                        builder: (context, ref, _) => InitialAvatar(
                          name: member.displayName,
                          radius: 17,
                          online: watchMemberPresence(
                            ref,
                            member,
                            transportAvailable:
                                ref.watch(imRealtimeAvailabilityProvider) ==
                                ImRealtimeAvailability.available,
                          ).online,
                          avatarKey: member.avatarKey,
                          avatarDataUrl: member.avatarDataUrl,
                        ),
                      ),
                      title: Text(
                        member.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                      subtitle: member.departmentName.isEmpty
                          ? null
                          : Text(
                              member.departmentName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.secondaryText,
                              ),
                            ),
                      onChanged: (selected) => setState(() {
                        if (selected == true) {
                          _selected.add(member.id);
                        } else {
                          _selected.remove(member.id);
                        }
                      }),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(60, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    key: const Key('create-group-submit'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(88, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: _title.text.trim().isEmpty
                        ? null
                        : () => Navigator.pop(
                            context,
                            _GroupDraft(
                              title: _title.text.trim(),
                              memberIds: _selected.toList(),
                            ),
                          ),
                    child: Text('创建（${_selected.length + 1}人）'),
                  ),
                ],
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

String _memberPresenceLabel(ImMemberPresence member, {DateTime? now}) {
  if (member.online == null) return '状态未知';
  if (member.online == true) return '在线';
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
