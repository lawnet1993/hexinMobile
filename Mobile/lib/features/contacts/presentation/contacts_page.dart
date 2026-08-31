import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../../shared/widgets/page_states.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/domain/collaboration_models.dart';

class ContactsPage extends ConsumerStatefulWidget {
  const ContactsPage({super.key, this.initialMode = 0})
    : assert(initialMode >= 0 && initialMode <= 3);

  final int initialMode;

  @override
  ConsumerState<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends ConsumerState<ContactsPage> {
  static const _contactPageSize = 30;

  Timer? _presenceRefreshTimer;
  String _query = '';
  String _selectedDepartmentId = '';
  int _visibleContactLimit = _contactPageSize;
  bool _openingConversation = false;
  bool _acceptingAll = false;
  late int _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _presenceRefreshTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _refreshContactPresence(),
    );
  }

  @override
  void didUpdateWidget(covariant ContactsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialMode != widget.initialMode) {
      _mode = widget.initialMode;
      _visibleContactLimit = _contactPageSize;
    }
  }

  @override
  void dispose() {
    _presenceRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshContactPresence() async {
    if (!mounted || _mode == 2) return;
    try {
      await ref.read(imRepositoryProvider).refreshBootstrap();
      if (mounted) ref.invalidate(imBootstrapProvider);
    } catch (_) {
      // Keep the last authoritative presence projection while offline.
    }
  }

  Future<void> _handleFriendApplication(
    ImFriendApplication application,
    bool accept,
  ) async {
    try {
      await ref
          .read(imRepositoryProvider)
          .handleFriendApplication(application.id, accept);
      ref.invalidate(pendingFriendApplicationsProvider);
      ref.invalidate(imBootstrapProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(accept ? '已添加为联系人' : '已拒绝申请')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('处理失败：$error')));
      }
    }
  }

  Future<void> _acceptAllFriendApplications(
    List<ImFriendApplication> applications,
  ) async {
    if (_acceptingAll || applications.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('全部接受'),
        content: Text('确认接受 ${applications.length} 条好友申请？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('接受'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _acceptingAll = true);
    try {
      final result = await ref
          .read(imRepositoryProvider)
          .acceptPendingFriendApplications(
            batchSize: applications.length.clamp(1, 500),
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已接受 ${result.processed} 条，剩余 ${result.remaining} 条'),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('批量接受失败：$error')));
      }
    } finally {
      ref.invalidate(pendingFriendApplicationsProvider);
      ref.invalidate(imBootstrapProvider);
      if (mounted) {
        setState(() => _acceptingAll = false);
      }
    }
  }

  Future<void> _openConversation(ImMember member) async {
    if (_openingConversation) return;
    setState(() => _openingConversation = true);
    try {
      final conversation = await ref
          .read(imRepositoryProvider)
          .createDirect(member.id);
      ref.invalidate(imBootstrapProvider);
      if (mounted) context.push('/chat/${conversation.id}');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('发起单聊失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _openingConversation = false);
    }
  }

  Future<void> _editRemark(ImMember member) async {
    ImMemberProfile profile;
    try {
      profile = await ref.read(imRepositoryProvider).memberProfile(member.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('资料加载失败：$error')));
      }
      return;
    }
    if (!mounted) return;
    final controller = TextEditingController(text: profile.remark);
    final remark = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('备注 ${member.displayName}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 128,
          decoration: const InputDecoration(labelText: '好友备注', isDense: true),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    await disposeRouteTextController(controller);
    if (remark == null || !mounted) return;
    try {
      await ref
          .read(imRepositoryProvider)
          .updateFriendRemark(member.id, remark);
      ref.invalidate(imBootstrapProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('备注已保存')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('保存失败：$error')));
      }
    }
  }

  Future<void> _searchOutsideDirectory() async {
    final result = await showModalBottomSheet<ImSearchResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _MemberSearchSheet(),
    );
    if (result == null || !mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    if (result.isFriend) {
      await _openConversation(
        ImMember(
          id: result.id,
          username: result.username,
          displayName: result.displayName,
          isOnline: false,
          isFriend: true,
          canStartDirect: true,
        ),
      );
      return;
    }
    final greeting = await _friendGreeting(result.displayName);
    if (greeting == null || !mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    try {
      await ref.read(imRepositoryProvider).requestFriend(result.id, greeting);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('好友申请已发送')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('好友申请发送失败：$error')));
      }
    }
  }

  Future<String?> _friendGreeting(String name) async {
    final controller = TextEditingController(text: '你好，我是公司同事');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('添加 $name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(labelText: '验证消息'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('发送'),
          ),
        ],
      ),
    );
    await disposeRouteTextController(controller);
    return result;
  }

  Future<void> _selectDepartment(
    List<ImDepartment> departments,
    List<ImMember> members,
  ) async {
    if (departments.isEmpty) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _DepartmentPickerSheet(
        departments: departments,
        members: members,
        selectedDepartmentId: _selectedDepartmentId,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedDepartmentId = selected;
      _visibleContactLimit = _contactPageSize;
    });
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(imBootstrapProvider);
    final applications = ref.watch(pendingFriendApplicationsProvider);
    final pendingCount = applications.value?.length ?? 0;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            EnterprisePageHeader(
              title: '通讯录',
              subtitle: value.value?.currentMember.departmentName,
              actions: [
                IconButton(
                  tooltip: '添加联系人',
                  onPressed: _searchOutsideDirectory,
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 20),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
              child: MobileSearchField(
                hintText: _mode == 3 ? '搜索群名称或消息' : '搜索姓名、部门或终端账号',
                onChanged: (value) => setState(() {
                  _query = value.trim().toLowerCase();
                  _visibleContactLimit = _contactPageSize;
                }),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  _DirectoryModeButton(
                    label: '组织',
                    selected: _mode == 0,
                    onTap: () => setState(() {
                      _mode = 0;
                      _visibleContactLimit = _contactPageSize;
                    }),
                  ),
                  const SizedBox(width: 8),
                  _DirectoryModeButton(
                    label: '好友',
                    selected: _mode == 1,
                    onTap: () => setState(() {
                      _mode = 1;
                      _visibleContactLimit = _contactPageSize;
                    }),
                  ),
                  const SizedBox(width: 8),
                  _DirectoryModeButton(
                    label: '群聊',
                    selected: _mode == 3,
                    onTap: () => setState(() => _mode = 3),
                  ),
                  const SizedBox(width: 8),
                  _DirectoryModeButton(
                    label: pendingCount > 0 ? '新朋友 $pendingCount' : '新朋友',
                    selected: _mode == 2,
                    onTap: () => setState(() => _mode = 2),
                  ),
                  if (_mode == 2 && pendingCount > 0) ...[
                    const Spacer(),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: _acceptingAll
                          ? null
                          : () => _acceptAllFriendApplications(
                              applications.value ?? const [],
                            ),
                      child: _acceptingAll
                          ? const SizedBox.square(
                              dimension: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('全部接受'),
                    ),
                  ],
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: MobileSurface(
                  child: _mode == 2
                      ? applications.when(
                          loading: () =>
                              const ModuleLoadingState(label: '正在加载好友申请'),
                          error: (error, _) => EmptyState(
                            icon: Icons.cloud_off_outlined,
                            title: '好友申请加载失败',
                            description: error.toString(),
                            onRetry: () => ref.invalidate(
                              pendingFriendApplicationsProvider,
                            ),
                          ),
                          data: (items) => items.isEmpty
                              ? const EmptyState(
                                  icon: Icons.person_add_alt_1_outlined,
                                  title: '暂无新的好友申请',
                                )
                              : RefreshIndicator(
                                  onRefresh: () => ref.refresh(
                                    pendingFriendApplicationsProvider.future,
                                  ),
                                  child: ListView.builder(
                                    itemCount: items.length,
                                    itemBuilder: (context, index) {
                                      final item = items[index];
                                      return _FriendApplicationTile(
                                        application: item,
                                        onAccept: () =>
                                            _handleFriendApplication(
                                              item,
                                              true,
                                            ),
                                        onReject: () =>
                                            _handleFriendApplication(
                                              item,
                                              false,
                                            ),
                                      );
                                    },
                                  ),
                                ),
                        )
                      : value.when(
                          loading: () =>
                              const ModuleLoadingState(label: '正在加载通讯录'),
                          error: (error, _) => EmptyState(
                            icon: Icons.cloud_off_outlined,
                            title: '通讯录加载失败',
                            description: error.toString(),
                            onRetry: () => ref.invalidate(imBootstrapProvider),
                          ),
                          data: (data) {
                            if (_mode == 3) {
                              final groups = data.conversations
                                  .where((item) => item.isGroup)
                                  .where(
                                    (item) =>
                                        _query.isEmpty ||
                                        item.title.toLowerCase().contains(
                                          _query,
                                        ) ||
                                        item.preview.toLowerCase().contains(
                                          _query,
                                        ),
                                  )
                                  .toList(growable: false);
                              if (groups.isEmpty) {
                                return const EmptyState(
                                  icon: Icons.groups_outlined,
                                  title: '暂无群聊',
                                );
                              }
                              return RefreshIndicator(
                                onRefresh: () async {
                                  ref.invalidate(imBootstrapProvider);
                                  await ref.read(imBootstrapProvider.future);
                                },
                                child: ListView.builder(
                                  itemCount: groups.length,
                                  itemBuilder: (context, index) {
                                    final group = groups[index];
                                    return _GroupConversationTile(
                                      conversation: group,
                                      onTap: () =>
                                          context.push('/chat/${group.id}'),
                                    );
                                  },
                                ),
                              );
                            }
                            final directory = ref.watch(imDepartmentsProvider);
                            final directoryItems =
                                directory.value ?? const <ImDepartment>[];
                            final members = _mode == 1
                                ? data.contacts
                                      .where((item) => item.isFriend)
                                      .toList(growable: false)
                                : _uniqueMembers([
                                    data.currentMember,
                                    ...data.contacts,
                                  ]);
                            final effectiveDepartmentId =
                                directoryItems.any(
                                  (item) => item.id == _selectedDepartmentId,
                                )
                                ? _selectedDepartmentId
                                : '';
                            final visibleDepartmentIds =
                                _departmentAndDescendantIds(
                                  directoryItems,
                                  effectiveDepartmentId,
                                );
                            final contacts = members.where((item) {
                              if (_mode == 0 &&
                                  effectiveDepartmentId.isNotEmpty &&
                                  !visibleDepartmentIds.contains(
                                    item.departmentId,
                                  )) {
                                return false;
                              }
                              return _query.isEmpty ||
                                  item.displayName.toLowerCase().contains(
                                    _query,
                                  ) ||
                                  item.username.toLowerCase().contains(
                                    _query,
                                  ) ||
                                  item.departmentName.toLowerCase().contains(
                                    _query,
                                  );
                            }).toList();
                            if (contacts.isEmpty) {
                              return Column(
                                children: [
                                  if (_mode == 0)
                                    _OrganizationDirectoryHeader(
                                      departmentName: _departmentLabel(
                                        directoryItems,
                                        effectiveDepartmentId,
                                      ),
                                      count: 0,
                                      onTap: () => _selectDepartment(
                                        directoryItems,
                                        members,
                                      ),
                                    ),
                                  const Expanded(
                                    child: EmptyState(
                                      icon: Icons.contacts_outlined,
                                      title: '暂无联系人',
                                    ),
                                  ),
                                ],
                              );
                            }
                            final shownContacts = contacts
                                .take(_visibleContactLimit)
                                .toList(growable: false);
                            final departments = _departmentGroups(
                              directoryItems,
                              shownContacts,
                            );
                            return RefreshIndicator(
                              onRefresh: () async {
                                ref.invalidate(imBootstrapProvider);
                                ref.invalidate(imDepartmentsProvider);
                                await Future.wait([
                                  ref.read(imBootstrapProvider.future),
                                  ref.read(imDepartmentsProvider.future),
                                ]);
                              },
                              child: ListView(
                                children: [
                                  if (_mode == 0)
                                    _OrganizationDirectoryHeader(
                                      departmentName: _departmentLabel(
                                        directoryItems,
                                        effectiveDepartmentId,
                                      ),
                                      count: contacts.length,
                                      onTap: () => _selectDepartment(
                                        directoryItems,
                                        members,
                                      ),
                                    ),
                                  for (final entry in departments)
                                    _DepartmentContacts(
                                      department: entry.label,
                                      depth: entry.depth,
                                      contacts: entry.contacts,
                                      currentMemberId: data.currentMember.id,
                                      showFriendActions: _mode == 1,
                                      onMessage: _openConversation,
                                      onRemark: _editRemark,
                                    ),
                                  if (contacts.length > shownContacts.length)
                                    Center(
                                      child: TextButton(
                                        key: const Key(
                                          'contacts-load-more-button',
                                        ),
                                        style: TextButton.styleFrom(
                                          minimumSize: const Size(96, 38),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        onPressed: () => setState(
                                          () => _visibleContactLimit +=
                                              _contactPageSize,
                                        ),
                                        child: Text(
                                          '加载更多（${shownContacts.length}/${contacts.length}）',
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ),
                                ],
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

class _OrganizationDirectoryHeader extends StatelessWidget {
  const _OrganizationDirectoryHeader({
    required this.departmentName,
    required this.count,
    required this.onTap,
  });

  final String departmentName;
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    key: const Key('organization-department-selector'),
    onTap: onTap,
    child: Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F2F5))),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.account_tree_outlined,
            size: 18,
            color: AppColors.primary,
          ),
          const SizedBox(width: 9),
          const Text(
            '企业通讯录',
            style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
          const SizedBox(width: 5),
          Text(
            '$count',
            style: const TextStyle(fontSize: 11, color: AppColors.weakText),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              departmentName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.secondaryText,
              ),
            ),
          ),
          const SizedBox(width: 2),
          const Icon(
            Icons.keyboard_arrow_down_rounded,
            size: 18,
            color: AppColors.secondaryText,
          ),
        ],
      ),
    ),
  );
}

class _DepartmentPickerSheet extends StatelessWidget {
  const _DepartmentPickerSheet({
    required this.departments,
    required this.members,
    required this.selectedDepartmentId,
  });

  final List<ImDepartment> departments;
  final List<ImMember> members;
  final String selectedDepartmentId;

  @override
  Widget build(BuildContext context) {
    final rows = _flattenDepartmentRows(departments);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * .64,
        child: Column(
          children: [
            const Text(
              '选择部门',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                children: [
                  _DepartmentPickerRow(
                    name: '全部部门',
                    count: members.length,
                    depth: 0,
                    selected: selectedDepartmentId.isEmpty,
                    onTap: () => Navigator.pop(context, ''),
                  ),
                  for (final row in rows)
                    _DepartmentPickerRow(
                      name: row.department.name,
                      count: members
                          .where(
                            (member) =>
                                member.departmentId == row.department.id,
                          )
                          .length,
                      depth: row.depth,
                      selected: selectedDepartmentId == row.department.id,
                      onTap: () => Navigator.pop(context, row.department.id),
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

class _DepartmentPickerRow extends StatelessWidget {
  const _DepartmentPickerRow({
    required this.name,
    required this.count,
    required this.depth,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final int count;
  final int depth;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: SizedBox(
      height: 44,
      child: Padding(
        padding: EdgeInsets.only(left: 16 + depth * 18, right: 16),
        child: Row(
          children: [
            Icon(
              depth == 0
                  ? Icons.account_tree_outlined
                  : Icons.subdirectory_arrow_right_rounded,
              size: 17,
              color: selected ? AppColors.primary : AppColors.secondaryText,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppColors.primary : null,
                ),
              ),
            ),
            Text(
              '$count',
              style: const TextStyle(fontSize: 11, color: AppColors.weakText),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 18,
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      size: 18,
                      color: AppColors.primary,
                    )
                  : null,
            ),
          ],
        ),
      ),
    ),
  );
}

final class _FlatDepartmentRow {
  const _FlatDepartmentRow({required this.department, required this.depth});

  final ImDepartment department;
  final int depth;
}

List<ImMember> _uniqueMembers(List<ImMember> members) {
  final ids = <String>{};
  return members.where((item) => ids.add(item.id)).toList(growable: false);
}

Set<String> _departmentAndDescendantIds(
  List<ImDepartment> departments,
  String departmentId,
) {
  if (departmentId.isEmpty) {
    return departments.map((item) => item.id).toSet();
  }
  final result = <String>{departmentId};
  var changed = true;
  while (changed) {
    changed = false;
    for (final item in departments) {
      if (result.contains(item.parentId) && result.add(item.id)) changed = true;
    }
  }
  return result;
}

String _departmentLabel(List<ImDepartment> departments, String departmentId) {
  if (departmentId.isEmpty) return '全部部门';
  for (final item in departments) {
    if (item.id == departmentId) return item.name;
  }
  return '全部部门';
}

List<_FlatDepartmentRow> _flattenDepartmentRows(
  List<ImDepartment> departments,
) {
  final byId = {for (final item in departments) item.id: item};
  final children = <String, List<ImDepartment>>{};
  for (final item in departments) {
    final parentId = byId.containsKey(item.parentId) ? item.parentId : '';
    children.putIfAbsent(parentId, () => []).add(item);
  }
  int compare(ImDepartment left, ImDepartment right) {
    final order = left.sortOrder.compareTo(right.sortOrder);
    return order != 0 ? order : left.name.compareTo(right.name);
  }

  for (final list in children.values) {
    list.sort(compare);
  }
  final rows = <_FlatDepartmentRow>[];
  final visited = <String>{};
  void append(String parentId, int depth) {
    for (final item in children[parentId] ?? const <ImDepartment>[]) {
      if (!visited.add(item.id)) continue;
      rows.add(_FlatDepartmentRow(department: item, depth: depth.clamp(0, 3)));
      append(item.id, depth + 1);
    }
  }

  append('', 0);
  for (final item in [...departments]..sort(compare)) {
    if (!visited.add(item.id)) continue;
    rows.add(_FlatDepartmentRow(department: item, depth: 0));
    append(item.id, 1);
  }
  return rows;
}

class _DirectoryModeButton extends StatelessWidget {
  const _DirectoryModeButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(8),
    onTap: onTap,
    child: Container(
      height: 32,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFE8F1FF) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? AppColors.primary : AppColors.secondaryText,
        ),
      ),
    ),
  );
}

class _FriendApplicationTile extends StatelessWidget {
  const _FriendApplicationTile({
    required this.application,
    required this.onAccept,
    required this.onReject,
  });

  final ImFriendApplication application;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 64,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
    leading: InitialAvatar(
      name: application.applicant.displayName,
      radius: 18,
      avatarDataUrl: application.applicant.avatarDataUrl,
    ),
    title: Text(
      application.applicant.displayName,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      application.greeting.isEmpty ? '请求添加你为联系人' : application.greeting,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 11, color: AppColors.secondaryText),
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(onPressed: onReject, child: const Text('拒绝')),
        const SizedBox(width: 2),
        FilledButton(onPressed: onAccept, child: const Text('接受')),
      ],
    ),
  );
}

class _GroupConversationTile extends StatelessWidget {
  const _GroupConversationTile({
    required this.conversation,
    required this.onTap,
  });

  final ImConversation conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 54,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
    leading: Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: const Color(0xFFE8F1FF),
        borderRadius: BorderRadius.circular(10),
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.groups_rounded,
        size: 20,
        color: AppColors.primary,
      ),
    ),
    title: Text(
      conversation.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    subtitle: Text(
      conversation.preview.isEmpty ? '群聊' : conversation.preview,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 10.5, color: AppColors.secondaryText),
    ),
    trailing: conversation.unreadCount > 0
        ? Container(
            width: conversation.unreadCount > 99 ? 30 : 18,
            height: 18,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFEA4335),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Text(
              conversation.unreadCount > 99
                  ? '99+'
                  : '${conversation.unreadCount}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        : const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: AppColors.weakText,
          ),
    onTap: onTap,
  );
}

final class _DepartmentContactGroup {
  const _DepartmentContactGroup({
    required this.label,
    required this.depth,
    required this.contacts,
  });

  final String label;
  final int depth;
  final List<ImMember> contacts;
}

List<_DepartmentContactGroup> _departmentGroups(
  List<ImDepartment> directory,
  List<ImMember> contacts,
) {
  final byId = {for (final item in directory) item.id: item};
  final membersByDepartment = <String, List<ImMember>>{};
  final fallbackByName = <String, List<ImMember>>{};
  for (final contact in contacts) {
    if (contact.departmentId.isNotEmpty &&
        byId.containsKey(contact.departmentId)) {
      membersByDepartment
          .putIfAbsent(contact.departmentId, () => [])
          .add(contact);
    } else {
      final name = contact.departmentName.trim().isEmpty
          ? '其他联系人'
          : contact.departmentName.trim();
      fallbackByName.putIfAbsent(name, () => []).add(contact);
    }
  }
  final children = <String, List<ImDepartment>>{};
  for (final item in directory) {
    final parentId = item.parentId.isNotEmpty && byId.containsKey(item.parentId)
        ? item.parentId
        : '';
    children.putIfAbsent(parentId, () => []).add(item);
  }
  int compareDepartment(ImDepartment left, ImDepartment right) {
    final byOrder = left.sortOrder.compareTo(right.sortOrder);
    return byOrder != 0 ? byOrder : left.name.compareTo(right.name);
  }

  for (final items in children.values) {
    items.sort(compareDepartment);
  }

  final result = <_DepartmentContactGroup>[];
  final visited = <String>{};
  void visit(ImDepartment item, List<String> path, int depth) {
    if (!visited.add(item.id)) return;
    final currentPath = [...path, item.name];
    final members = membersByDepartment[item.id];
    if (members != null && members.isNotEmpty) {
      result.add(
        _DepartmentContactGroup(
          label: currentPath.join(' / '),
          depth: depth.clamp(0, 2),
          contacts: members,
        ),
      );
    }
    for (final child in children[item.id] ?? const <ImDepartment>[]) {
      visit(child, currentPath, depth + 1);
    }
  }

  for (final root in children[''] ?? const <ImDepartment>[]) {
    visit(root, const [], 0);
  }
  // Defensive handling for cyclic or orphaned server data.
  for (final item in [...directory]..sort(compareDepartment)) {
    if (!visited.contains(item.id)) visit(item, const [], 0);
  }
  for (final entry in fallbackByName.entries) {
    result.add(
      _DepartmentContactGroup(
        label: entry.key,
        depth: 0,
        contacts: entry.value,
      ),
    );
  }
  return result;
}

class _DepartmentContacts extends StatelessWidget {
  const _DepartmentContacts({
    required this.department,
    this.depth = 0,
    required this.contacts,
    required this.currentMemberId,
    required this.showFriendActions,
    required this.onMessage,
    required this.onRemark,
  });

  final String department;
  final int depth;
  final List<ImMember> contacts;
  final String currentMemberId;
  final bool showFriendActions;
  final ValueChanged<ImMember> onMessage;
  final ValueChanged<ImMember> onRemark;

  @override
  Widget build(BuildContext context) => Theme(
    data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
    child: ExpansionTile(
      initiallyExpanded: true,
      shape: const Border(),
      collapsedShape: const Border(),
      tilePadding: EdgeInsets.only(left: 12 + depth * 14, right: 12),
      childrenPadding: EdgeInsets.zero,
      leading: const Icon(
        Icons.account_tree_outlined,
        size: 18,
        color: AppColors.primary,
      ),
      title: Text(
        department,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      trailing: Text(
        '${contacts.length}',
        style: const TextStyle(color: AppColors.secondaryText),
      ),
      children: contacts.map((contact) {
        final isCurrentMember = contact.id == currentMemberId;
        return ListTile(
          minTileHeight: 48,
          contentPadding: const EdgeInsets.only(left: 14, right: 4),
          leading: InitialAvatar(
            name: contact.displayName,
            radius: 17,
            online: contact.isOnline,
            avatarDataUrl: contact.avatarDataUrl,
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(
                  contact.displayName.isEmpty
                      ? contact.username
                      : contact.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (isCurrentMember) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F1FF),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '我',
                    style: TextStyle(
                      fontSize: 9.5,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
          subtitle: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: contact.username),
                const TextSpan(text: '  ·  '),
                TextSpan(
                  text: _contactPresenceLabel(contact),
                  style: TextStyle(
                    color: contact.isOnline
                        ? AppColors.success
                        : AppColors.weakText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.secondaryText,
            ),
          ),
          trailing: isCurrentMember
              ? null
              : showFriendActions && contact.isFriend
              ? PopupMenuButton<String>(
                  tooltip: '联系人操作',
                  iconSize: 18,
                  padding: EdgeInsets.zero,
                  onSelected: (value) {
                    if (value == 'message') onMessage(contact);
                    if (value == 'remark') onRemark(contact);
                  },
                  itemBuilder: (_) => [
                    if (contact.canStartDirect)
                      const PopupMenuItem(
                        value: 'message',
                        height: 40,
                        child: Text('发消息'),
                      ),
                    const PopupMenuItem(
                      value: 'remark',
                      height: 40,
                      child: Text('修改备注'),
                    ),
                  ],
                )
              : IconButton(
                  tooltip: '发送消息',
                  onPressed: contact.canStartDirect
                      ? () => onMessage(contact)
                      : null,
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                ),
          onTap: !isCurrentMember && contact.canStartDirect
              ? () => onMessage(contact)
              : null,
        );
      }).toList(),
    ),
  );
}

String _contactPresenceLabel(ImMember member, {DateTime? now}) {
  if (member.isOnline) return '在线';
  final lastSeenAt = member.lastSeenAt?.toLocal();
  if (lastSeenAt == null) return '离线';
  final current = (now ?? DateTime.now()).toLocal();
  final currentDay = DateTime(current.year, current.month, current.day);
  final seenDay = DateTime(lastSeenAt.year, lastSeenAt.month, lastSeenAt.day);
  final dayDifference = currentDay.difference(seenDay).inDays;
  final hour = lastSeenAt.hour.toString().padLeft(2, '0');
  final minute = lastSeenAt.minute.toString().padLeft(2, '0');
  if (dayDifference == 0) return '最近上线 $hour:$minute';
  if (dayDifference == 1) return '最近上线 昨天';
  final month = lastSeenAt.month.toString().padLeft(2, '0');
  final day = lastSeenAt.day.toString().padLeft(2, '0');
  return '最近上线 $month-$day';
}

class _MemberSearchSheet extends ConsumerStatefulWidget {
  const _MemberSearchSheet();

  @override
  ConsumerState<_MemberSearchSheet> createState() => _MemberSearchSheetState();
}

class _MemberSearchSheetState extends ConsumerState<_MemberSearchSheet> {
  List<ImSearchResult> _items = const [];
  bool _loading = false;
  String _query = '';
  String _error = '';

  Future<void> _search() async {
    final query = _query.trim();
    if (query.isEmpty || _loading) {
      setState(() => _error = query.isEmpty ? '请输入完整终端账号' : '');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = '';
      _items = const [];
    });
    try {
      final items = await ref.read(imRepositoryProvider).searchMembers(query);
      if (mounted && _query.trim() == query) {
        setState(() => _items = items);
      }
    } catch (error) {
      if (mounted && _query.trim() == query) {
        setState(() => _error = '搜索失败：$error');
      }
    } finally {
      if (mounted && _query.trim() == query) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .64,
      child: Column(
        children: [
          const Text(
            '添加联系人',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 38,
                    child: TextField(
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(fontSize: 14),
                      onChanged: (value) => setState(() {
                        _query = value;
                        _error = '';
                        _items = const [];
                      }),
                      onSubmitted: (_) => _search(),
                      decoration: const InputDecoration(
                        hintText: '输入完整终端账号',
                        prefixIcon: Icon(Icons.search_rounded, size: 18),
                        prefixIconConstraints: BoxConstraints(minWidth: 38),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 36,
                  child: FilledButton(
                    onPressed: _loading ? null : _search,
                    child: Text(
                      _loading ? '搜索中' : '搜索',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _error,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _query.trim().isEmpty
                ? const EmptyState(
                    icon: Icons.person_search_outlined,
                    title: '输入账号后搜索',
                  )
                : _items.isEmpty && !_loading && _error.isEmpty
                ? const EmptyState(
                    icon: Icons.person_off_outlined,
                    title: '没有找到联系人',
                  )
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return ListTile(
                        dense: true,
                        minTileHeight: 50,
                        leading: InitialAvatar(
                          name: item.displayName,
                          radius: 18,
                        ),
                        title: Text(
                          item.displayName,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          item.username,
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: Text(
                          item.isFriend ? '发消息' : '添加',
                          style: const TextStyle(fontSize: 12),
                        ),
                        onTap: () => Navigator.pop(context, item),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}
