import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/errors/mobile_error_text.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../../shared/widgets/page_states.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/domain/collaboration_models.dart';

class MessageAssistantPage extends ConsumerStatefulWidget {
  const MessageAssistantPage({super.key});

  @override
  ConsumerState<MessageAssistantPage> createState() =>
      _MessageAssistantPageState();
}

class _MessageAssistantPageState extends ConsumerState<MessageAssistantPage> {
  final _contentController = TextEditingController();
  final _pageScrollController = ScrollController();
  final _selectedIds = <String>{};
  final _additionalTasks = <ImAssistantTask>[];
  String _receiverKeyword = '';
  bool _submitting = false;
  bool _loadingMoreTasks = false;
  int _nextTaskPage = 2;
  bool _taskHasMore = false;
  bool _taskAutoLoadScheduled = false;
  bool _taskAutoLoadRetryBlocked = false;
  bool _taskPagingExhausted = false;

  @override
  void initState() {
    super.initState();
    _pageScrollController.addListener(_onPageScroll);
  }

  @override
  void dispose() {
    _contentController.dispose();
    _pageScrollController
      ..removeListener(_onPageScroll)
      ..dispose();
    super.dispose();
  }

  void _resetTaskPages() {
    if (!mounted) return;
    setState(() {
      _additionalTasks.clear();
      _nextTaskPage = 2;
      _loadingMoreTasks = false;
      _taskHasMore = false;
      _taskAutoLoadRetryBlocked = false;
      _taskPagingExhausted = false;
    });
    ref.invalidate(imAssistantTasksPageProvider);
    ref.invalidate(imAssistantTasksProvider);
  }

  Future<void> _loadMoreTasks() async {
    if (_loadingMoreTasks || !_taskHasMore || _taskAutoLoadRetryBlocked) {
      return;
    }
    final pageNumber = _nextTaskPage;
    setState(() => _loadingMoreTasks = true);
    try {
      final page = await ref.read(
        imAssistantTasksPageProvider(pageNumber).future,
      );
      if (!mounted) return;
      final knownIds = _additionalTasks.map((item) => item.id).toSet();
      setState(() {
        _additionalTasks.addAll(
          page.items.where((item) => knownIds.add(item.id)),
        );
        _nextTaskPage = page.page + 1;
        _taskAutoLoadRetryBlocked = false;
        _taskPagingExhausted = page.items.isEmpty;
      });
    } catch (error) {
      _taskAutoLoadRetryBlocked = true;
      ref.invalidate(imAssistantTasksPageProvider(pageNumber));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('加载更多失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _loadingMoreTasks = false);
    }
  }

  void _onPageScroll() {
    if (_taskAutoLoadRetryBlocked ||
        !_pageScrollController.hasClients ||
        _pageScrollController.position.extentAfter > 240) {
      return;
    }
    unawaited(_loadMoreTasks());
  }

  bool _handlePageScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _taskAutoLoadRetryBlocked = false;
    }
    return false;
  }

  void _scheduleTaskAutoLoad() {
    if (!_taskHasMore ||
        _loadingMoreTasks ||
        _taskAutoLoadScheduled ||
        _taskAutoLoadRetryBlocked) {
      return;
    }
    _taskAutoLoadScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _taskAutoLoadScheduled = false;
      if (!mounted || !_pageScrollController.hasClients) return;
      if (_pageScrollController.position.extentAfter <= 240) {
        unawaited(_loadMoreTasks());
      }
    });
  }

  Future<void> _create() async {
    if (_submitting ||
        _selectedIds.isEmpty ||
        _contentController.text.trim().isEmpty) {
      return;
    }
    setState(() => _submitting = true);
    try {
      await ref
          .read(imRepositoryProvider)
          .createAssistantTask(
            receiverMemberIds: _selectedIds.toList(),
            content: _contentController.text,
          );
      _contentController.clear();
      _selectedIds.clear();
      _resetTaskPages();
      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('批量消息任务已创建')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('创建失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _cancel(ImAssistantTask task) async {
    try {
      await ref.read(imRepositoryProvider).cancelAssistantTask(task.id);
      _resetTaskPages();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('取消失败：$error')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bootstrap = ref.watch(imBootstrapProvider);
    final tasks = ref.watch(imAssistantTasksPageProvider(1));
    final presenceAvailable =
        ref.watch(imRealtimeAvailabilityProvider) ==
        ImRealtimeAvailability.available;
    return Scaffold(
      appBar: AppBar(title: const Text('群发助手')),
      body: SafeArea(
        child: bootstrap.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => EmptyState(
            icon: Icons.cloud_off_outlined,
            title: '数据加载失败',
            description: mobileErrorText(error),
          ),
          data: (data) {
            if (!data.permissions.batchSend) {
              return const EmptyState(
                icon: Icons.lock_outline_rounded,
                title: '当前账号无批量发送权限',
              );
            }
            final contacts =
                data.contacts
                    .where((item) => item.id != data.currentMember.id)
                    .toList()
                  ..sort((left, right) {
                    if (presenceAvailable && left.isOnline != right.isOnline) {
                      return left.isOnline ? -1 : 1;
                    }
                    return left.displayName.compareTo(right.displayName);
                  });
            final keyword = _receiverKeyword.toLowerCase();
            final visibleContacts = contacts.where((member) {
              return keyword.isEmpty ||
                  member.displayName.toLowerCase().contains(keyword) ||
                  member.username.toLowerCase().contains(keyword) ||
                  member.departmentName.toLowerCase().contains(keyword);
            }).toList();
            return NotificationListener<ScrollNotification>(
              onNotification: _handlePageScrollNotification,
              child: ListView(
                key: const Key('assistant-page-scroll'),
                controller: _pageScrollController,
                padding: const EdgeInsets.all(12),
                children: [
                  MobileSurface(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '新建任务',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _contentController,
                          minLines: 2,
                          maxLines: 4,
                          maxLength: 2000,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            hintText: '输入要发送的消息',
                            counterText: '',
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        MobileSearchField(
                          hintText: '搜索姓名、账号或部门',
                          onChanged: (value) =>
                              setState(() => _receiverKeyword = value.trim()),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          height: 32,
                          child: Row(
                            children: [
                              Text(
                                '已选 ${_selectedIds.length} 人',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.secondaryText,
                                ),
                              ),
                              const Spacer(),
                              TextButton(
                                onPressed: visibleContacts.isEmpty
                                    ? null
                                    : () => setState(
                                        () => _selectedIds.addAll(
                                          visibleContacts.map(
                                            (item) => item.id,
                                          ),
                                        ),
                                      ),
                                child: const Text('全选'),
                              ),
                              TextButton(
                                onPressed: _selectedIds.isEmpty
                                    ? null
                                    : () => setState(_selectedIds.clear),
                                child: const Text('清空'),
                              ),
                            ],
                          ),
                        ),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 196),
                          child: visibleContacts.isEmpty
                              ? const SizedBox(
                                  height: 72,
                                  child: Center(
                                    child: Text(
                                      '未找到接收人',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.secondaryText,
                                      ),
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: visibleContacts.length,
                                  itemBuilder: (context, index) {
                                    final member = visibleContacts[index];
                                    final selected = _selectedIds.contains(
                                      member.id,
                                    );
                                    void toggle() => setState(() {
                                      selected
                                          ? _selectedIds.remove(member.id)
                                          : _selectedIds.add(member.id);
                                    });
                                    return ListTile(
                                      dense: true,
                                      visualDensity: const VisualDensity(
                                        vertical: -2,
                                      ),
                                      contentPadding: EdgeInsets.zero,
                                      leading: InitialAvatar(
                                        name: member.displayName,
                                        radius: 15,
                                        online: presenceAvailable
                                            ? member.isOnline
                                            : null,
                                        avatarKey: member.avatarKey,
                                        avatarDataUrl: member.avatarDataUrl,
                                      ),
                                      title: Text(
                                        member.displayName,
                                        style: const TextStyle(fontSize: 13.5),
                                      ),
                                      subtitle: member.departmentName.isEmpty
                                          ? null
                                          : Text(
                                              member.departmentName,
                                              style: const TextStyle(
                                                fontSize: 10.5,
                                                color: AppColors.secondaryText,
                                              ),
                                            ),
                                      trailing: Transform.scale(
                                        scale: .86,
                                        child: Checkbox(
                                          value: selected,
                                          onChanged: (_) => toggle(),
                                        ),
                                      ),
                                      onTap: toggle,
                                    );
                                  },
                                ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 40,
                          child: FilledButton(
                            onPressed:
                                _submitting ||
                                    _selectedIds.isEmpty ||
                                    _contentController.text.trim().isEmpty
                                ? null
                                : _create,
                            child: Text(_submitting ? '提交中…' : '提交群发任务'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      '任务记录',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 6),
                  tasks.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => EmptyState(
                      icon: Icons.error_outline_rounded,
                      title: '任务加载失败',
                      description: mobileErrorText(error),
                      onRetry: _resetTaskPages,
                    ),
                    data: (page) {
                      final knownIds = <String>{};
                      final items = <ImAssistantTask>[
                        ...page.items.where((item) => knownIds.add(item.id)),
                        ..._additionalTasks.where(
                          (item) => knownIds.add(item.id),
                        ),
                      ];
                      final hasMore =
                          !_taskPagingExhausted && items.length < page.total;
                      _taskHasMore = hasMore;
                      _scheduleTaskAutoLoad();
                      return items.isEmpty
                          ? const EmptyState(
                              icon: Icons.campaign_outlined,
                              title: '暂无批量消息任务',
                            )
                          : MobileSurface(
                              child: Column(
                                children: [
                                  ...items.map((task) {
                                    final time = task.createdAt == null
                                        ? ''
                                        : DateFormat(
                                            'MM-dd HH:mm',
                                          ).format(task.createdAt!.toLocal());
                                    return ListTile(
                                      dense: true,
                                      title: Text(
                                        task.content,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        [
                                          if (time.isNotEmpty) time,
                                          _assistantStatusLabel(task.status),
                                          '成功 ${task.successCount}/${task.receiverCount}',
                                          if (task.failureCount > 0)
                                            '失败 ${task.failureCount}',
                                        ].join(' · '),
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      trailing: task.canCancel
                                          ? TextButton(
                                              onPressed: () => _cancel(task),
                                              child: const Text('取消'),
                                            )
                                          : task.failureCount > 0
                                          ? Text(
                                              '${task.failureCount} 失败',
                                              style: const TextStyle(
                                                color: Color(0xFFD54941),
                                                fontSize: 12,
                                              ),
                                            )
                                          : null,
                                    );
                                  }),
                                  if (hasMore)
                                    SizedBox(
                                      key: const Key(
                                        'assistant-task-page-footer',
                                      ),
                                      height: 40,
                                      child: Center(
                                        child: _loadingMoreTasks
                                            ? const SizedBox.square(
                                                dimension: 17,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : Text(
                                                '继续上滑 · ${items.length}/${page.total}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: AppColors.weakText,
                                                ),
                                              ),
                                      ),
                                    ),
                                ],
                              ),
                            );
                    },
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

String _assistantStatusLabel(String value) =>
    switch (value.trim().toLowerCase()) {
      'pending' => '待发送',
      'queued' => '排队中',
      'running' => '发送中',
      'completed' || 'succeeded' || 'success' => '已完成',
      'failed' => '发送失败',
      'cancelled' || 'canceled' => '已取消',
      _ => value.trim().isEmpty ? '状态未知' : value,
    };
