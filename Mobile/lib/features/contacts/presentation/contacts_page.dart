import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/diagnostics/chat_open_diagnostics.dart';
import '../../../shared/errors/mobile_error_text.dart';
import '../../../shared/widgets/mobile_bottom_sheets.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../../shared/widgets/page_states.dart';
import '../../../shared/widgets/visible_refresh_scheduler.dart';
import '../../../core/storage/secure_session_store.dart';
import '../../auth/application/auth_controller.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/data/im_member_presence.dart';
import '../../collaboration/domain/collaboration_models.dart';

typedef ContactPresenceRefresher = Future<void> Function();
typedef MemberAccountSearcher = Future<List<ImSearchResult>> Function(
  String account,
);

final contactPresenceRefresherProvider = Provider<ContactPresenceRefresher>((
  ref,
) {
  return () => ref.read(imRepositoryProvider).refreshBootstrap();
});

final memberAccountSearcherProvider = Provider<MemberAccountSearcher>((ref) {
  return ref.read(imRepositoryProvider).searchMembers;
});

final contactConversationCreatorProvider =
    Provider<Future<ImConversation> Function(String)>((ref) {
      return ref.read(imRepositoryProvider).createDirect;
    });

enum _MemberSearchAction { message, friendRequest }

final class _MemberSearchSelection {
  const _MemberSearchSelection({required this.result, required this.action});

  final ImSearchResult result;
  final _MemberSearchAction action;
}

class ContactsPage extends ConsumerStatefulWidget {
  const ContactsPage({super.key, this.initialMode = 0})
    : assert(initialMode >= 0 && initialMode <= 3);

  final int initialMode;

  @override
  ConsumerState<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends ConsumerState<ContactsPage> {
  static const _contactPageSize = 30;

  late final VisibleRefreshScheduler _presenceRefreshScheduler;
  Future<void>? _presenceRefreshFuture;
  bool _presenceRefreshFailed = true;
  final _contactsScrollController = ScrollController();
  String _query = '';
  String _selectedDepartmentId = '';
  int _visibleContactLimit = _contactPageSize;
  int _visibleContactTotal = 0;
  final Set<String> _expandedDepartmentIds = <String>{};
  final Set<String> _collapsedFlatDepartmentIds = <String>{};
  bool _organizationTreeActive = false;
  bool _contactAutoExpandScheduled = false;
  bool _openingConversation = false;
  bool _acceptingAll = false;
  late int _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _contactsScrollController.addListener(_onContactsScroll);
    _presenceRefreshScheduler = VisibleRefreshScheduler(
      _refreshContactPresence,
    );
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
  void didUpdateWidget(covariant ContactsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialMode != widget.initialMode) {
      _mode = widget.initialMode;
      _resetContactWindow();
      if (_mode != 2) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          unawaited(_refreshContactPresence());
        });
      }
    }
  }

  @override
  void dispose() {
    _presenceRefreshScheduler.dispose();
    _contactsScrollController
      ..removeListener(_onContactsScroll)
      ..dispose();
    super.dispose();
  }

  void _resetContactWindow() {
    _visibleContactLimit = _contactPageSize;
    _visibleContactTotal = 0;
    _expandedDepartmentIds.clear();
    _collapsedFlatDepartmentIds.clear();
    _organizationTreeActive = false;
    _contactAutoExpandScheduled = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_contactsScrollController.hasClients) return;
      _contactsScrollController.jumpTo(0);
    });
  }

  void _onContactsScroll() {
    if (!_contactsScrollController.hasClients ||
        _contactsScrollController.position.extentAfter > 240) {
      return;
    }
    if (!_organizationTreeActive) _expandContactWindow();
  }

  void _expandContactWindow() {
    if (_visibleContactLimit >= _visibleContactTotal) return;
    final next = _visibleContactLimit + _contactPageSize;
    setState(() {
      _visibleContactLimit = next < _visibleContactTotal
          ? next
          : _visibleContactTotal;
    });
  }

  void _scheduleContactAutoExpand() {
    if (_visibleContactLimit >= _visibleContactTotal ||
        _contactAutoExpandScheduled) {
      return;
    }
    _contactAutoExpandScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _contactAutoExpandScheduled = false;
      if (!mounted || !_contactsScrollController.hasClients) return;
      if (_contactsScrollController.position.extentAfter <= 240) {
        _expandContactWindow();
      }
    });
  }

  Future<void> _refreshContactPresence() {
    if (!mounted || _mode == 2) return Future<void>.value();
    return _presenceRefreshFuture ??= _performContactPresenceRefresh()
        .whenComplete(() => _presenceRefreshFuture = null);
  }

  Future<void> _performContactPresenceRefresh() async {
    final session = ref.read(authControllerProvider).value;
    bool stillCurrent() {
      if (!mounted) return false;
      final current = ref.read(authControllerProvider).value;
      return session == null
          ? current == null
          : current?.isSameSession(session) == true;
    }

    try {
      await ref.read(contactPresenceRefresherProvider)();
      if (!stillCurrent()) return;
      setState(() => _presenceRefreshFailed = false);
      ref.invalidate(imBootstrapProvider);
    } on SessionChangedException {
      // An obsolete account request must not affect the new account's status.
    } catch (_) {
      if (stillCurrent()) setState(() => _presenceRefreshFailed = true);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileActionErrorText('处理失败', error))),
        );
      }
    }
  }

  Future<void> _acceptAllFriendApplications(
    List<ImFriendApplication> applications,
  ) async {
    if (_acceptingAll || applications.isEmpty) return;
    final confirmed = await showMobileConfirmSheet(
      context,
      title: '全部接受',
      message: '确认接受 ${applications.length} 条好友申请？',
      confirmLabel: '接受',
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileActionErrorText('批量接受失败', error))),
        );
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
    // Lock before the first await, including cached routes. Keep the lock until
    // the chat is popped so queued taps cannot stack identical chat pages.
    _openingConversation = true;
    final openTrace = ChatOpenDiagnostics.begin();
    try {
      FocusManager.instance.primaryFocus?.unfocus();
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      openTrace?.mark(ChatOpenStage.keyboardHidden);
      if (!mounted) return;
      final bootstrap = ref.read(imBootstrapProvider).value;
      final existing = bootstrap == null
          ? null
          : existingDirectConversationForMember(bootstrap, member);
      if (existing != null) {
        openTrace?.bind(existing.id);
        await context.push<void>('/chat/${existing.id}', extra: existing);
        return;
      }
      final conversation = await ref.read(contactConversationCreatorProvider)(
        member.id,
      );
      if (!mounted) return;
      ref.invalidate(imBootstrapProvider);
      openTrace?.bind(conversation.id);
      await context.push<void>('/chat/${conversation.id}', extra: conversation);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileActionErrorText('发起单聊失败', error))),
        );
      }
    } finally {
      openTrace?.finish(ChatOpenEnd.routeClosed);
      _openingConversation = false;
    }
  }

  Future<void> _editRemark(ImMember member) async {
    ImMemberProfile profile;
    try {
      profile = await ref.read(imRepositoryProvider).memberProfile(member.id);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileActionErrorText('资料加载失败', error))),
        );
      }
      return;
    }
    if (!mounted) return;
    final remark = await showMobileTextInputSheet(
      context,
      title: '修改备注',
      subtitle: member.displayName,
      initialValue: profile.remark,
      label: '好友备注',
      hintText: '请输入备注',
      maxLength: 128,
    );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileActionErrorText('保存失败', error))),
        );
      }
    }
  }

  Future<void> _searchOutsideDirectory() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final currentMember = ref.read(imBootstrapProvider).value?.currentMember;
    final selection = await showModalBottomSheet<_MemberSearchSelection>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: false,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: _MemberSearchSheet(currentMemberId: currentMember?.id ?? ''),
      ),
    );
    if (selection == null || !mounted) return;
    await Future<void>.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    final result = selection.result;
    if (selection.action == _MemberSearchAction.message) {
      await _openConversation(
        ImMember(
          id: result.id,
          username: result.username,
          displayName: result.displayName,
          isOnline: result.isOnline,
          avatarKey: result.avatarKey,
          avatarDataUrl: result.avatarDataUrl,
          departmentName: result.departmentName,
          isFriend: result.isFriend,
          canStartDirect: result.canStartDirect,
        ),
      );
      return;
    }
    try {
      final senderName = currentMember?.displayName.trim() ?? '';
      await ref
          .read(imRepositoryProvider)
          .requestFriend(
            result.id,
            senderName.isEmpty ? '你好' : '我是$senderName',
          );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('好友申请已发送')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileActionErrorText('好友申请发送失败', error))),
        );
      }
    }
  }

  Future<void> _selectDepartment(
    List<ImDepartment> departments,
    List<ImMember> members,
  ) async {
    if (departments.isEmpty) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final selected = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: false,
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
      _resetContactWindow();
    });
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(imBootstrapProvider);
    final directory = ref.watch(imDepartmentsProvider);
    final presenceAvailable =
        ref.watch(imRealtimeAvailabilityProvider) ==
            ImRealtimeAvailability.available &&
        !_presenceRefreshFailed;
    final pickerMembers = value.value == null
        ? const <ImMember>[]
        : _uniqueMembers([
            value.value!.currentMember,
            ...value.value!.contacts,
          ]);
    final applications = ref.watch(pendingFriendApplicationsProvider);
    final pendingCount = applications.value?.length ?? 0;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            EnterprisePageHeader(
              title: '通讯录',
              subtitle: value.value?.currentMember.departmentName,
              actions: [
                IconButton(
                  tooltip: '添加好友',
                  style: compactHeaderIconButtonStyle,
                  onPressed: _searchOutsideDirectory,
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 20),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 2, 12, 6),
              child: Row(
                children: [
                  Expanded(
                    child: MobileSearchField(
                      key: const Key('contacts-search-field'),
                      hintText: _mode == 3 ? '搜索群名称或消息' : '搜索姓名或部门',
                      onChanged: (value) => setState(() {
                        _query = value.trim().toLowerCase();
                        _resetContactWindow();
                      }),
                    ),
                  ),
                  if (_mode == 0) ...[
                    const SizedBox(width: 6),
                    SizedBox.square(
                      dimension: 40,
                      child: IconButton(
                        key: const Key('organization-department-selector'),
                        tooltip: '选择部门',
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(
                          foregroundColor: _selectedDepartmentId.isEmpty
                              ? AppColors.secondaryText
                              : AppColors.primary,
                        ),
                        onPressed: value.value == null
                            ? null
                            : () => _selectDepartment(
                                directory.value ?? const <ImDepartment>[],
                                pickerMembers,
                              ),
                        icon: Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _selectedDepartmentId.isEmpty
                                ? const Color(0xFFF1F3F6)
                                : const Color(0xFFE8F1FF),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.account_tree_outlined,
                            size: 18,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
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
                      _resetContactWindow();
                    }),
                  ),
                  const SizedBox(width: 8),
                  _DirectoryModeButton(
                    label: '好友',
                    selected: _mode == 1,
                    onTap: () => setState(() {
                      _mode = 1;
                      _resetContactWindow();
                    }),
                  ),
                  const SizedBox(width: 8),
                  _DirectoryModeButton(
                    label: '群聊',
                    selected: _mode == 3,
                    onTap: () => setState(() {
                      _mode = 3;
                      _resetContactWindow();
                    }),
                  ),
                  const SizedBox(width: 8),
                  _DirectoryModeButton(
                    label: pendingCount > 0 ? '新朋友 $pendingCount' : '新朋友',
                    selected: _mode == 2,
                    onTap: () => setState(() {
                      _mode = 2;
                      _resetContactWindow();
                    }),
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
                child: Material(
                  key: const Key('contacts-flat-content'),
                  type: MaterialType.transparency,
                  child: _mode == 2
                      ? applications.when(
                          loading: () =>
                              const ModuleLoadingState(label: '正在加载好友申请'),
                          error: (error, _) => EmptyState(
                            icon: Icons.cloud_off_outlined,
                            title: '好友申请加载失败',
                            description: mobileErrorText(error),
                            onRetry: () => ref.invalidate(
                              pendingFriendApplicationsProvider,
                            ),
                          ),
                          data: (items) => items.isEmpty
                              ? _CompactDirectoryEmpty(
                                  key: const Key('new-friends-empty'),
                                  label: '暂无新的好友申请',
                                  onRefresh: () => ref.refresh(
                                    pendingFriendApplicationsProvider.future,
                                  ),
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
                            description: mobileErrorText(error),
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
                                  await _refreshContactPresence();
                                },
                                child: ListView.builder(
                                  itemCount: groups.length,
                                  itemBuilder: (context, index) {
                                    final group = groups[index];
                                    return _GroupConversationTile(
                                      conversation: group,
                                      onTap: () async {
                                        FocusManager.instance.primaryFocus
                                            ?.unfocus();
                                        await SystemChannels.textInput
                                            .invokeMethod<void>(
                                              'TextInput.hide',
                                            );
                                        if (context.mounted) {
                                          context.push('/chat/${group.id}');
                                        }
                                      },
                                    );
                                  },
                                ),
                              );
                            }
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
                            final organizationTreeActive =
                                _mode == 0 && _query.isEmpty;
                            if (contacts.isEmpty && !organizationTreeActive) {
                              return const EmptyState(
                                icon: Icons.contacts_outlined,
                                title: '暂无联系人',
                              );
                            }
                            final shownContacts = organizationTreeActive
                                ? contacts
                                : contacts
                                      .take(_visibleContactLimit)
                                      .toList(growable: false);
                            _organizationTreeActive = organizationTreeActive;
                            if (organizationTreeActive) {
                              _visibleContactTotal = 0;
                            } else {
                              _visibleContactTotal = contacts.length;
                              _scheduleContactAutoExpand();
                            }
                            final departments = organizationTreeActive
                                ? _departmentTree(
                                    directoryItems,
                                    shownContacts,
                                    rootDepartmentId: effectiveDepartmentId,
                                  )
                                : _flatDepartmentGroups(
                                    directoryItems,
                                    shownContacts,
                                  );
                            final rows = _visibleContactRows(
                              departments,
                              organizationTree: organizationTreeActive,
                              expanded: _expandedDepartmentIds,
                              collapsedFlat: _collapsedFlatDepartmentIds,
                            );
                            final rowIndices = <Key, int>{
                              for (var i = 0; i < rows.length; i++)
                                rows[i].key: i,
                            };
                            final hasMore =
                                !organizationTreeActive &&
                                contacts.length > shownContacts.length;
                            return RefreshIndicator(
                              onRefresh: () async {
                                ref.invalidate(imDepartmentsProvider);
                                await Future.wait([
                                  _refreshContactPresence(),
                                  ref.read(imDepartmentsProvider.future),
                                ]);
                              },
                              child: ListView.builder(
                                key: const Key('contacts-page-scroll'),
                                controller: _contactsScrollController,
                                scrollCacheExtent:
                                    const ScrollCacheExtent.pixels(192),
                                itemCount: rows.length + (hasMore ? 1 : 0),
                                findChildIndexCallback: (key) =>
                                    rowIndices[key],
                                itemBuilder: (context, index) {
                                  if (index == rows.length) {
                                    return Padding(
                                      key: const Key('contacts-page-footer'),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 10,
                                      ),
                                      child: Center(
                                        child: Text(
                                          '继续上滑 · ${shownContacts.length}/${contacts.length}',
                                          style: const TextStyle(
                                            color: AppColors.weakText,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    );
                                  }
                                  final row = rows[index];
                                  final member = row.member;
                                  if (member != null) {
                                    return _ContactListMember(
                                      key: row.key,
                                      contact: member,
                                      currentMemberId: data.currentMember.id,
                                      presenceAvailable: presenceAvailable,
                                      showFriendActions: _mode == 1,
                                      onMessage: _openConversation,
                                      onRemark: _editRemark,
                                    );
                                  }
                                  final department = row.department;
                                  return _DepartmentHeader(
                                    key: row.key,
                                    department: department,
                                    expanded: organizationTreeActive
                                        ? _expandedDepartmentIds.contains(
                                            department.id,
                                          )
                                        : !_collapsedFlatDepartmentIds.contains(
                                            department.id,
                                          ),
                                    onExpanded: (expanded) => setState(() {
                                      final ids = organizationTreeActive
                                          ? _expandedDepartmentIds
                                          : _collapsedFlatDepartmentIds;
                                      if (organizationTreeActive
                                          ? expanded
                                          : !expanded) {
                                        ids.add(department.id);
                                      } else {
                                        ids.remove(department.id);
                                      }
                                    }),
                                  );
                                },
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

/// Returns an unambiguous existing direct conversation for [member].
///
/// The bootstrap endpoint does not expose a direct peer id, so the same
/// desktop-compatible title projection used by the chat UI is matched here.
/// Ambiguous display names deliberately fall back to the idempotent server
/// endpoint instead of opening another person's conversation.
ImConversation? existingDirectConversationForMember(
  ImBootstrap bootstrap,
  ImMember member,
) {
  final aliases = <String>{
    member.displayName.trim().toLowerCase(),
    member.username.trim().toLowerCase(),
  }..remove('');
  if (aliases.isEmpty) return null;

  final matches = bootstrap.conversations
      .where((conversation) {
        if (!conversation.isDirect) return false;
        final titleParts = conversation.title
            .split(RegExp(r'[、,，]'))
            .map((part) => part.trim().toLowerCase())
            .where((part) => part.isNotEmpty)
            .toSet();
        return titleParts.any(aliases.contains);
      })
      .toList(growable: false);
  return matches.length == 1 ? matches.single : null;
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
        key: const Key('department-picker-sheet'),
        height: MediaQuery.sizeOf(context).height * .64,
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
            const SizedBox(height: 4),
            SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.only(left: 16, right: 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '选择部门',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const Key('department-picker-close'),
                      tooltip: '关闭',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 19),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 2),
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
  Widget build(BuildContext context) => SizedBox(
    key: ValueKey('directory-mode-$label'),
    height: 40,
    child: InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Center(
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
      ),
    ),
  );
}

class _CompactDirectoryEmpty extends StatelessWidget {
  const _CompactDirectoryEmpty({
    super.key,
    required this.label,
    required this.onRefresh,
  });

  final String label;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) => RefreshIndicator(
    onRefresh: onRefresh,
    child: ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 44),
      children: [
        Center(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.weakText),
          ),
        ),
      ],
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
      avatarKey: application.applicant.avatarKey,
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
    required this.id,
    required this.label,
    required this.depth,
    required this.contacts,
    this.children = const [],
    int? totalContactCount,
  }) : totalContactCount = totalContactCount ?? contacts.length;

  final String id;
  final String label;
  final int depth;
  final List<ImMember> contacts;
  final List<_DepartmentContactGroup> children;
  final int totalContactCount;
}

List<_DepartmentContactGroup> _flatDepartmentGroups(
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
          id: item.id,
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
        id: 'fallback:${entry.key}',
        label: entry.key,
        depth: 0,
        contacts: entry.value,
      ),
    );
  }
  return result;
}

List<_DepartmentContactGroup> _departmentTree(
  List<ImDepartment> directory,
  List<ImMember> contacts, {
  String rootDepartmentId = '',
}) {
  final allById = {for (final item in directory) item.id: item};
  final includedIds = rootDepartmentId.isEmpty
      ? allById.keys.toSet()
      : _departmentAndDescendantIds(directory, rootDepartmentId);
  final included = directory
      .where((item) => includedIds.contains(item.id))
      .toList(growable: false);
  final byId = {for (final item in included) item.id: item};
  final membersByDepartment = <String, List<ImMember>>{};
  final fallbackMembers = <ImMember>[];
  for (final contact in contacts) {
    if (contact.departmentId.isNotEmpty &&
        byId.containsKey(contact.departmentId)) {
      membersByDepartment
          .putIfAbsent(contact.departmentId, () => [])
          .add(contact);
    } else {
      fallbackMembers.add(contact);
    }
  }
  final children = <String, List<ImDepartment>>{};
  for (final item in included) {
    final parentId = byId.containsKey(item.parentId) ? item.parentId : '';
    children.putIfAbsent(parentId, () => []).add(item);
  }
  int compareDepartment(ImDepartment left, ImDepartment right) {
    final byOrder = left.sortOrder.compareTo(right.sortOrder);
    return byOrder != 0 ? byOrder : left.name.compareTo(right.name);
  }

  for (final items in children.values) {
    items.sort(compareDepartment);
  }

  final visited = <String>{};
  _DepartmentContactGroup build(ImDepartment item, int depth) {
    visited.add(item.id);
    final childGroups = <_DepartmentContactGroup>[
      for (final child in children[item.id] ?? const <ImDepartment>[])
        if (!visited.contains(child.id)) build(child, depth + 1),
    ];
    final directContacts = membersByDepartment[item.id] ?? const <ImMember>[];
    return _DepartmentContactGroup(
      id: item.id,
      label: item.name,
      depth: depth.clamp(0, 3),
      contacts: directContacts,
      children: childGroups,
      totalContactCount:
          directContacts.length +
          childGroups.fold<int>(
            0,
            (total, child) => total + child.totalContactCount,
          ),
    );
  }

  final result = <_DepartmentContactGroup>[
    for (final root in children[''] ?? const <ImDepartment>[])
      if (!visited.contains(root.id)) build(root, 0),
  ];
  // Defensive handling for cyclic or orphaned server data.
  for (final item in [...included]..sort(compareDepartment)) {
    if (!visited.contains(item.id)) result.add(build(item, 0));
  }
  if (fallbackMembers.isNotEmpty) {
    result.add(
      _DepartmentContactGroup(
        id: 'fallback:other',
        label: '其他联系人',
        depth: 0,
        contacts: fallbackMembers,
      ),
    );
  }
  return result;
}

// Only the open tree is projected into rows. Member widgets (and their presence
// subscriptions/avatars) are created by the outer sliver for the viewport.
class _ContactListEntry {
  const _ContactListEntry(this.department, [this.member]);
  final _DepartmentContactGroup department;
  final ImMember? member;
  Key get key => ValueKey(
    member == null
        ? 'department-group-${department.id}'
        : 'contact-${department.id}-${member!.id}',
  );
}

List<_ContactListEntry> _visibleContactRows(
  List<_DepartmentContactGroup> departments, {
  required bool organizationTree,
  required Set<String> expanded,
  required Set<String> collapsedFlat,
}) {
  final rows = <_ContactListEntry>[];
  void append(_DepartmentContactGroup department) {
    rows.add(_ContactListEntry(department));
    final isExpanded = organizationTree
        ? expanded.contains(department.id)
        : !collapsedFlat.contains(department.id);
    if (!isExpanded) return;
    for (final child in department.children) {
      append(child);
    }
    for (final member in department.contacts) {
      rows.add(_ContactListEntry(department, member));
    }
  }

  for (final department in departments) {
    append(department);
  }
  return rows;
}

class _DepartmentHeader extends StatelessWidget {
  const _DepartmentHeader({
    super.key,
    required this.department,
    required this.expanded,
    required this.onExpanded,
  });
  final _DepartmentContactGroup department;
  final bool expanded;
  final ValueChanged<bool> onExpanded;

  @override
  Widget build(BuildContext context) {
    final canExpand =
        department.children.isNotEmpty || department.contacts.isNotEmpty;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: ValueKey('department-toggle-${department.id}-$expanded'),
        initiallyExpanded: expanded,
        onExpansionChanged: canExpand ? onExpanded : null,
        showTrailingIcon: canExpand,
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        shape: const Border(),
        collapsedShape: const Border(),
        minTileHeight: 44,
        tilePadding: EdgeInsets.only(
          left: 12 + department.depth * 14,
          right: 8,
        ),
        childrenPadding: EdgeInsets.zero,
        leading: const Icon(
          Icons.account_tree_outlined,
          size: 18,
          color: AppColors.primary,
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                department.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${department.totalContactCount}',
              style: const TextStyle(
                color: AppColors.secondaryText,
                fontSize: 11.5,
              ),
            ),
          ],
        ),
        children: const [],
      ),
    );
  }
}

class _ContactListMember extends ConsumerWidget {
  const _ContactListMember({
    super.key,
    required this.contact,
    required this.currentMemberId,
    required this.presenceAvailable,
    required this.showFriendActions,
    required this.onMessage,
    required this.onRemark,
  });
  final ImMember contact;
  final String currentMemberId;
  final bool presenceAvailable;
  final bool showFriendActions;
  final ValueChanged<ImMember> onMessage;
  final ValueChanged<ImMember> onRemark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCurrentMember = contact.id == currentMemberId;
    final presence = watchMemberPresence(
      ref,
      contact,
      transportAvailable: presenceAvailable,
    );
    return ListTile(
      minTileHeight: 48,
      contentPadding: const EdgeInsets.only(left: 14, right: 4),
      leading: Semantics(
        button: !isCurrentMember && contact.canStartDirect,
        label: contact.canStartDirect
            ? '联系${contact.displayName}'
            : contact.displayName,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: !isCurrentMember && contact.canStartDirect
              ? () => onMessage(contact)
              : null,
          child: InitialAvatar(
            name: contact.displayName,
            radius: 17,
            online: presence.online,
            avatarKey: contact.avatarKey,
            avatarDataUrl: contact.avatarDataUrl,
          ),
        ),
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
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
      subtitle: Text(
        _contactPresenceLabel(presence),
        style: TextStyle(
          fontSize: 10.5,
          color: presence.online == true
              ? AppColors.success
              : AppColors.weakText,
          fontWeight: FontWeight.w600,
        ),
      ),
      trailing: isCurrentMember
          ? null
          : showFriendActions && contact.isFriend
          ? IconButton(
              tooltip: '联系人操作',
              onPressed: () async {
                final value = await showMobileChoiceSheet<String>(
                  context,
                  title: contact.displayName,
                  options: [
                    if (contact.canStartDirect)
                      const MobileSheetOption(
                        value: 'message',
                        label: '发消息',
                        icon: Icons.chat_bubble_outline_rounded,
                      ),
                    const MobileSheetOption(
                      value: 'remark',
                      label: '修改备注',
                      icon: Icons.edit_note_rounded,
                    ),
                  ],
                );
                if (!context.mounted || value == null) return;
                if (value == 'message') onMessage(contact);
                if (value == 'remark') onRemark(contact);
              },
              icon: const Icon(Icons.more_horiz_rounded, size: 18),
            )
          : null,
      onTap: !isCurrentMember && contact.canStartDirect
          ? () => onMessage(contact)
          : null,
    );
  }
}

String _contactPresenceLabel(ImMemberPresence member, {DateTime? now}) {
  if (member.online == null) return '状态未知';
  if (member.online == true) return '在线';
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
  const _MemberSearchSheet({required this.currentMemberId});

  final String currentMemberId;

  @override
  ConsumerState<_MemberSearchSheet> createState() => _MemberSearchSheetState();
}

class _MemberSearchSheetState extends ConsumerState<_MemberSearchSheet> {
  final TextEditingController _controller = TextEditingController();
  List<ImSearchResult> _items = const [];

  ImMember? get _presenceMember => _items.isEmpty
      ? null
      : ImMember(
          id: _items.first.id,
          username: _items.first.username,
          displayName: _items.first.displayName,
          isOnline: _items.first.isOnline,
        );
  bool _loading = false;
  String _query = '';
  String _error = '';
  bool _hasSearched = false;
  int _searchGeneration = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _query.trim();
    if (query.isEmpty || _loading) {
      setState(() => _error = query.isEmpty ? '请输入完整终端账号' : '');
      return;
    }
    FocusScope.of(context).unfocus();
    final generation = ++_searchGeneration;
    setState(() {
      _loading = true;
      _error = '';
      _items = const [];
    });
    try {
      final items = await ref.read(memberAccountSearcherProvider)(query);
      if (mounted && generation == _searchGeneration) {
        setState(() {
          _hasSearched = true;
          _items = items
              .where((item) => item.id != widget.currentMemberId)
              .take(1)
              .toList(growable: false);
        });
      }
    } catch (error) {
      if (mounted && generation == _searchGeneration) {
        setState(() => _error = mobileActionErrorText('搜索失败', error));
      }
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      key: const Key('friend-search-sheet'),
      height: (MediaQuery.sizeOf(context).height * .34)
          .clamp(240.0, 290.0)
          .toDouble(),
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
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 2),
            child: SizedBox(
              height: 40,
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '添加好友',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('friend-search-close'),
                    tooltip: '关闭',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: TextField(
                      key: const Key('friend-search-field'),
                      controller: _controller,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(fontSize: 14),
                      onChanged: (value) => setState(() {
                        // Editing releases the previous lookup. Its late result
                        // must not match a newly submitted copy of the same text.
                        _searchGeneration++;
                        _query = value;
                        _error = '';
                        _items = const [];
                        _hasSearched = false;
                        _loading = false;
                      }),
                      onSubmitted: (_) => _search(),
                      decoration: const InputDecoration(
                        hintText: '输入完整终端账号',
                        prefixIcon: Icon(Icons.search_rounded, size: 18),
                        prefixIconConstraints: BoxConstraints(
                          minWidth: 36,
                          minHeight: 34,
                        ),
                        isDense: true,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 36,
                  child: FilledButton(
                    key: const Key('friend-search-submit'),
                    onPressed: _loading ? null : _search,
                    child: Text(
                      _loading ? '查找中' : '查找',
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
            child:
                _query.trim().isEmpty ||
                    (!_hasSearched && !_loading && _error.isEmpty)
                ? Center(
                    child: Text(
                      _query.trim().isEmpty ? '输入完整终端账号后查找' : '点击查找',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.weakText,
                      ),
                    ),
                  )
                : _items.isEmpty
                ? _loading || _error.isNotEmpty
                      ? const SizedBox.shrink()
                      : const Center(
                          child: Text(
                            '未找到该终端账号',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.weakText,
                            ),
                          ),
                        )
                : Align(
                    alignment: Alignment.topCenter,
                    child: Container(
                      key: const Key('friend-search-result'),
                      margin: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLow,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Consumer(
                            builder: (context, ref, _) => InitialAvatar(
                              name: _items.first.displayName,
                              radius: 18,
                              online: watchMemberPresence(
                                ref,
                                _presenceMember,
                                transportAvailable:
                                    ref.watch(imRealtimeAvailabilityProvider) ==
                                    ImRealtimeAvailability.available,
                              ).online,
                              avatarKey: _items.first.avatarKey,
                              avatarDataUrl: _items.first.avatarDataUrl,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _items.first.displayName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Consumer(
                                  builder: (context, ref, _) => Text(
                                    [
                                      _items.first.departmentName,
                                      _contactPresenceLabel(
                                        watchMemberPresence(
                                          ref,
                                          _presenceMember,
                                          transportAvailable:
                                              ref.watch(
                                                imRealtimeAvailabilityProvider,
                                              ) ==
                                              ImRealtimeAvailability.available,
                                        ),
                                      ),
                                    ].where((item) => item.isNotEmpty).join(' · '),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: AppColors.secondaryText,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          SizedBox(
                            height: 32,
                            child: FilledButton(
                              key: const Key('friend-search-action'),
                              onPressed: () => Navigator.pop(
                                context,
                                _MemberSearchSelection(
                                  result: _items.first,
                                  action: _items.first.canStartDirect
                                      ? _MemberSearchAction.message
                                      : _MemberSearchAction.friendRequest,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                              child: Text(
                                _items.first.canStartDirect ? '发消息' : '申请好友',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    ),
  );
}
