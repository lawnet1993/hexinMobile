import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../../shared/widgets/page_states.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/domain/collaboration_models.dart';

class GroupManagementPage extends ConsumerStatefulWidget {
  const GroupManagementPage({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<GroupManagementPage> createState() =>
      _GroupManagementPageState();
}

class _GroupManagementPageState extends ConsumerState<GroupManagementPage> {
  int _tab = 0;
  bool _loading = true;
  String? _error;
  ImGroupManagementCapabilities _capabilities =
      const ImGroupManagementCapabilities();
  ImGroupProfile? _profile;
  List<ImMember> _managers = const [];
  List<ImMutedGroupMember> _muted = const [];
  List<ImGroupJoinRequest> _requests = const [];
  List<ImGroupNotice> _notices = const [];
  int _mutedPage = 1;
  int _mutedTotal = 0;
  int _managersPage = 1;
  int _managersTotal = 0;
  int _requestsPage = 1;
  int _requestsTotal = 0;
  int _noticesPage = 1;
  int _noticesTotal = 0;
  bool _loadingMore = false;
  bool _deletingHistory = false;
  String _historyDeletionStatus = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repository = ref.read(imRepositoryProvider);
      final values = await Future.wait<Object?>([
        repository.groupManagementCapabilities(widget.conversationId),
        repository.groupManagersPage(widget.conversationId),
        repository.groupMutedMembers(widget.conversationId),
        repository.groupJoinRequests(widget.conversationId),
        repository.groupNotices(widget.conversationId),
        repository.refreshGroupProfile(widget.conversationId),
      ]);
      if (!mounted) return;
      final managers = values[1] as ImGroupManagementPage<ImMember>;
      final muted = values[2] as ImGroupManagementPage<ImMutedGroupMember>;
      final requests = values[3] as ImGroupManagementPage<ImGroupJoinRequest>;
      final notices = values[4] as ImGroupManagementPage<ImGroupNotice>;
      setState(() {
        _capabilities = values[0] as ImGroupManagementCapabilities;
        _managers = managers.items;
        _managersPage = managers.page;
        _managersTotal = managers.total;
        _muted = muted.items;
        _mutedPage = muted.page;
        _mutedTotal = muted.total;
        _requests = requests.items;
        _requestsPage = requests.page;
        _requestsTotal = requests.total;
        _notices = notices.items;
        _noticesPage = notices.page;
        _noticesTotal = notices.total;
        _profile = values[5] as ImGroupProfile?;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _tab == 4) return;
    final repository = ref.read(imRepositoryProvider);
    setState(() => _loadingMore = true);
    try {
      if (_tab == 0 && _muted.length < _mutedTotal) {
        final result = await repository.groupMutedMembers(
          widget.conversationId,
          page: _mutedPage + 1,
        );
        if (!mounted) return;
        setState(() {
          _muted = _mergeByKey(_muted, result.items, (item) => item.member.id);
          _mutedPage = result.page;
          _mutedTotal = result.total;
        });
      } else if (_tab == 1 && _requests.length < _requestsTotal) {
        final result = await repository.groupJoinRequests(
          widget.conversationId,
          page: _requestsPage + 1,
        );
        if (!mounted) return;
        setState(() {
          _requests = _mergeByKey(_requests, result.items, (item) => item.id);
          _requestsPage = result.page;
          _requestsTotal = result.total;
        });
      } else if (_tab == 2 && _managers.length < _managersTotal) {
        final result = await repository.groupManagersPage(
          widget.conversationId,
          page: _managersPage + 1,
        );
        if (!mounted) return;
        setState(() {
          _managers = _mergeByKey(_managers, result.items, (item) => item.id);
          _managersPage = result.page;
          _managersTotal = result.total;
        });
      } else if (_tab == 3 && _notices.length < _noticesTotal) {
        final result = await repository.groupNotices(
          widget.conversationId,
          page: _noticesPage + 1,
        );
        if (!mounted) return;
        setState(() {
          _notices = _mergeByKey(_notices, result.items, (item) => item.id);
          _noticesPage = result.page;
          _noticesTotal = result.total;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('加载更多失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _deleteAllHistory() async {
    final profile = _profile;
    if (profile == null || _deletingHistory) return;
    var confirmation = '';
    var reason = '';
    final draft = await showDialog<_HistoryDeletionDraft>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('删除所有人的聊天记录'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '服务器消息、附件、收藏、已读和提及记录将异步删除，所有成员都无法恢复。',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: '删除原因',
                    isDense: true,
                  ),
                  onChanged: (value) => setDialogState(() => reason = value),
                ),
                const SizedBox(height: 8),
                TextField(
                  decoration: InputDecoration(
                    labelText: '输入群名确认：${profile.title}',
                    isDense: true,
                  ),
                  onChanged: (value) =>
                      setDialogState(() => confirmation = value),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed:
                  reason.trim().isEmpty || confirmation.trim() != profile.title
                  ? null
                  : () => Navigator.pop(
                      dialogContext,
                      _HistoryDeletionDraft(confirmation.trim(), reason.trim()),
                    ),
              child: const Text('确认删除'),
            ),
          ],
        ),
      ),
    );
    if (draft == null || !mounted) return;
    setState(() {
      _deletingHistory = true;
      _historyDeletionStatus = '正在删除服务器群历史…';
    });
    try {
      final job = await ref
          .read(imRepositoryProvider)
          .deleteAllGroupHistory(
            widget.conversationId,
            confirmation: draft.confirmation,
            reason: draft.reason,
          );
      if (!mounted) return;
      if (job.isCompleted) {
        ref.invalidate(conversationMessagesProvider(widget.conversationId));
        setState(
          () => _historyDeletionStatus =
              '删除完成，共删除 ${job.deletedMessageCount} 条群消息',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已删除 ${job.deletedMessageCount} 条群消息')),
        );
      } else if (job.isFailed) {
        final detail = job.errorMessage.trim().isEmpty
            ? '后台删除失败'
            : job.errorMessage;
        setState(() => _historyDeletionStatus = '删除失败：$detail');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$detail')));
      } else {
        const detail = '任务仍在后台处理，可稍后重新进入查看';
        setState(() => _historyDeletionStatus = detail);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text(detail)));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _historyDeletionStatus = '删除失败：$error');
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('删除失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _deletingHistory = false);
    }
  }

  Future<void> _unmute(ImMutedGroupMember item) async {
    try {
      await ref
          .read(imRepositoryProvider)
          .updateGroupMemberMute(widget.conversationId, item.member.id, null);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('解除禁言失败：$error')));
      }
    }
  }

  Future<void> _handle(ImGroupJoinRequest item, bool accept) async {
    try {
      await ref
          .read(imRepositoryProvider)
          .handleGroupJoinRequest(widget.conversationId, item.id, accept);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('入群申请处理失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F6F8),
    appBar: AppBar(title: const Text('群管理')),
    body: Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
          child: Row(
            children: [
              _Tab(
                label: '禁言 $_mutedTotal',
                selected: _tab == 0,
                onTap: () => setState(() => _tab = 0),
              ),
              _Tab(
                label: '入群 $_requestsTotal',
                selected: _tab == 1,
                onTap: () => setState(() => _tab = 1),
              ),
              _Tab(
                label: '管理员 $_managersTotal',
                selected: _tab == 2,
                onTap: () => setState(() => _tab = 2),
              ),
              _Tab(
                label: '记录 $_noticesTotal',
                selected: _tab == 3,
                onTap: () => setState(() => _tab = 3),
              ),
              _Tab(
                label: '高级',
                selected: _tab == 4,
                onTap: () => setState(() => _tab = 4),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _error != null
              ? EmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: '群管理加载失败',
                  description: _error,
                  onRetry: _load,
                )
              : RefreshIndicator(onRefresh: _load, child: _content()),
        ),
      ],
    ),
  );

  Widget _content() {
    if (_tab == 0) {
      if (_muted.isEmpty) return const _EmptyList(label: '暂无禁言成员');
      final hasMore = _muted.length < _mutedTotal;
      return ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _muted.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, _) =>
            const Divider(height: 1, indent: 58, color: AppColors.border),
        itemBuilder: (_, index) {
          if (index == _muted.length) {
            return _LoadMoreRow(loading: _loadingMore, onTap: _loadMore);
          }
          final item = _muted[index];
          return ListTile(
            dense: true,
            leading: InitialAvatar(
              name: item.member.displayName,
              radius: 17,
              online: item.member.isOnline,
              avatarDataUrl: item.member.avatarDataUrl,
            ),
            title: Text(
              item.member.displayName,
              style: const TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              item.mutedUntil == null
                  ? '持续禁言'
                  : '至 ${DateFormat('MM-dd HH:mm').format(item.mutedUntil!.toLocal())}',
              style: const TextStyle(fontSize: 10.5),
            ),
            trailing: _capabilities.canMuteMembers
                ? TextButton(
                    onPressed: () => _unmute(item),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('解除'),
                  )
                : null,
          );
        },
      );
    }
    if (_tab == 1) {
      if (_requests.isEmpty) return const _EmptyList(label: '暂无待审核申请');
      final hasMore = _requests.length < _requestsTotal;
      return ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _requests.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, _) =>
            const Divider(height: 1, indent: 58, color: AppColors.border),
        itemBuilder: (_, index) {
          if (index == _requests.length) {
            return _LoadMoreRow(loading: _loadingMore, onTap: _loadMore);
          }
          final item = _requests[index];
          return ListTile(
            dense: true,
            leading: InitialAvatar(name: item.applicantName, radius: 17),
            title: Text(
              item.applicantName,
              style: const TextStyle(fontSize: 13),
            ),
            subtitle: Text(
              item.createdAt == null
                  ? item.status
                  : DateFormat('MM-dd HH:mm').format(item.createdAt!.toLocal()),
              style: const TextStyle(fontSize: 10.5),
            ),
            trailing: _capabilities.canReviewJoinRequests
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => _handle(item, false),
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('拒绝'),
                      ),
                      FilledButton(
                        onPressed: () => _handle(item, true),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(52, 32),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('通过'),
                      ),
                    ],
                  )
                : null,
          );
        },
      );
    }
    if (_tab == 2) {
      if (_managers.isEmpty) return const _EmptyList(label: '暂无群管理员');
      final hasMore = _managers.length < _managersTotal;
      return ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _managers.length + (hasMore ? 1 : 0),
        separatorBuilder: (_, _) =>
            const Divider(height: 1, indent: 58, color: AppColors.border),
        itemBuilder: (_, index) {
          if (index == _managers.length) {
            return _LoadMoreRow(loading: _loadingMore, onTap: _loadMore);
          }
          final item = _managers[index];
          final isOwner = item.groupRole.toLowerCase() == 'owner';
          return ListTile(
            dense: true,
            leading: InitialAvatar(
              name: item.displayName,
              radius: 17,
              online: item.isOnline,
              avatarDataUrl: item.avatarDataUrl,
            ),
            title: Text(item.displayName, style: const TextStyle(fontSize: 13)),
            subtitle: Text(
              item.username,
              style: const TextStyle(fontSize: 10.5),
            ),
            trailing: Text(
              isOwner ? '群主' : '管理员',
              style: TextStyle(
                fontSize: 11,
                color: isOwner ? AppColors.primary : AppColors.secondaryText,
              ),
            ),
          );
        },
      );
    }
    if (_tab == 4) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
        children: [
          const Text(
            '危险操作',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (_capabilities.canDeleteAllHistory)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MobileSurface(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.delete_sweep_outlined,
                      color: Colors.red,
                    ),
                    title: const Text('删除所有人的聊天记录'),
                    subtitle: const Text('删除服务器群历史，所有成员均不可恢复'),
                    trailing: _deletingHistory
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.chevron_right_rounded),
                    onTap: _deletingHistory ? null : _deleteAllHistory,
                  ),
                ),
                if (_historyDeletionStatus.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
                    child: Text(
                      _historyDeletionStatus,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ),
              ],
            )
          else
            const _EmptyList(label: '当前账号没有高级群管理权限'),
        ],
      );
    }
    if (_notices.isEmpty) return const _EmptyList(label: '暂无群操作记录');
    final hasMore = _notices.length < _noticesTotal;
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: _notices.length + (hasMore ? 1 : 0),
      separatorBuilder: (_, _) =>
          const Divider(height: 1, indent: 18, color: AppColors.border),
      itemBuilder: (_, index) {
        if (index == _notices.length) {
          return _LoadMoreRow(loading: _loadingMore, onTap: _loadMore);
        }
        final item = _notices[index];
        return ListTile(
          dense: true,
          leading: const Icon(
            Icons.history_rounded,
            size: 19,
            color: AppColors.primary,
          ),
          title: Text(
            item.actorName.isEmpty
                ? _noticeLabel(item.type)
                : '${item.actorName} · ${_noticeLabel(item.type)}',
            style: const TextStyle(fontSize: 13),
          ),
          trailing: item.createdAt == null
              ? null
              : Text(
                  DateFormat('MM-dd HH:mm').format(item.createdAt!.toLocal()),
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.secondaryText,
                  ),
                ),
        );
      },
    );
  }
}

List<T> _mergeByKey<T>(
  List<T> current,
  List<T> incoming,
  String Function(T item) keyOf,
) {
  final merged = <String, T>{for (final item in current) keyOf(item): item};
  for (final item in incoming) {
    merged[keyOf(item)] = item;
  }
  return merged.values.toList(growable: false);
}

class _LoadMoreRow extends StatelessWidget {
  const _LoadMoreRow({required this.loading, required this.onTap});

  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: Center(
      child: loading
          ? const SizedBox.square(
              dimension: 17,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : TextButton(onPressed: onTap, child: const Text('加载更多')),
    ),
  );
}

final class _HistoryDeletionDraft {
  const _HistoryDeletionDraft(this.confirmation, this.reason);

  final String confirmation;
  final String reason;
}

String _noticeLabel(String type) => switch (type.toLowerCase()) {
  'group.created' => '创建了群聊',
  'group.member.muted' => '禁言了群成员',
  'group.member.unmuted' => '解除了群成员禁言',
  'group.member.joined' => '成员加入群聊',
  'group.member.removed' => '移出了群成员',
  'group.notice.updated' => '更新了群公告',
  'group.profile.updated' => '更新了群资料',
  _ => type,
};

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE8F1FF) : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppColors.primary : AppColors.secondaryText,
          ),
        ),
      ),
    ),
  );
}

class _EmptyList extends StatelessWidget {
  const _EmptyList({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [
      SizedBox(
        height: 280,
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.secondaryText,
            ),
          ),
        ),
      ),
    ],
  );
}
