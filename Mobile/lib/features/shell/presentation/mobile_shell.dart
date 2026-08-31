import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../network/application/tunnel_controller.dart';
import '../../../core/theme/tdesign_icons.dart';
import '../../../core/artifacts/mobile_artifact_repository.dart';
import '../../../core/notifications/mobile_push_registration.dart';
import '../../../core/updates/client_update_repository.dart';
import '../../../core/security/managed_security_repository.dart';
import '../../auth/application/auth_controller.dart';
import '../../collaboration/application/im_sync_coordinator.dart';
import '../../collaboration/application/mobile_device_authorization_coordinator.dart';
import '../../collaboration/application/mobile_presence_coordinator.dart';
import '../../collaboration/application/oa_catalog_sync_coordinator.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../../core/theme/app_colors.dart';

class MobileShell extends ConsumerStatefulWidget {
  const MobileShell({super.key, required this.navigationShell});
  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends ConsumerState<MobileShell>
    with WidgetsBindingObserver {
  String? _lastPromptedReleaseId;
  final Set<String> _promptedInspectionIds = {};
  late final MobilePresenceCoordinator _presenceCoordinator;
  late final ImSyncCoordinator _imSyncCoordinator;
  late final OaSyncCoordinator _oaSyncCoordinator;
  late final MobileDeviceAuthorizationCoordinator
  _deviceAuthorizationCoordinator;
  late final MobilePushRegistration _pushRegistration;
  late final ManagedTerminalCommandCoordinator _terminalCommandCoordinator;

  @override
  void initState() {
    super.initState();
    _presenceCoordinator = ref.read(mobilePresenceCoordinatorProvider);
    _imSyncCoordinator = ref.read(imSyncCoordinatorProvider);
    _oaSyncCoordinator = ref.read(oaCatalogSyncCoordinatorProvider);
    _deviceAuthorizationCoordinator = ref.read(
      mobileDeviceAuthorizationCoordinatorProvider,
    );
    _pushRegistration = ref.read(mobilePushRegistrationProvider);
    _terminalCommandCoordinator = ref.read(
      managedTerminalCommandCoordinatorProvider,
    );
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _synchronizeRuntime();
      _synchronizeCollaboration();
      _checkClientUpdate();
      _checkActiveInspection();
      _terminalCommandCoordinator.start();
    });
  }

  Future<void> _synchronizeCollaboration() async {
    try {
      await _deviceAuthorizationCoordinator.synchronize();
    } catch (_) {
      // Device authorization is retried on app resume and remains visible in
      // the dedicated device page when collaboration is temporarily offline.
    }
    if (!mounted) return;
    try {
      await _pushRegistration.start(onOpenRoute: _openPushRoute);
    } catch (_) {
      // Push registration must not block local cache and foreground sync.
    }
    if (!mounted) return;
    await _presenceCoordinator.start();
    if (!mounted) return;
    await _imSyncCoordinator.start();
    if (!mounted) return;
    await _oaSyncCoordinator.start();
  }

  void _openPushRoute(String route) {
    if (!mounted) return;
    context.go(route);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pushRegistration.stop();
    _presenceCoordinator.stop();
    _imSyncCoordinator.stop();
    _oaSyncCoordinator.stop();
    _terminalCommandCoordinator.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _imSyncCoordinator.synchronizeNow();
      _presenceCoordinator.synchronizeNow();
      _oaSyncCoordinator.synchronizeNow();
      _pushRegistration.synchronize().ignore();
      _deviceAuthorizationCoordinator.synchronize().ignore();
      _checkClientUpdate();
      _checkActiveInspection();
      _terminalCommandCoordinator.synchronizeNow();
    }
  }

  Future<void> _checkClientUpdate() async {
    try {
      final update = await ref
          .read(clientUpdateRepositoryProvider)
          .checkLatest();
      if (!mounted || update == null) return;
      if (!update.isMandatory && _lastPromptedReleaseId == update.releaseId) {
        return;
      }
      _lastPromptedReleaseId = update.releaseId;
      await showDialog<void>(
        context: context,
        barrierDismissible: !update.isMandatory,
        builder: (context) => PopScope(
          canPop: !update.isMandatory,
          child: AlertDialog(
            title: Text(update.isMandatory ? '必须更新客户端' : '发现新版本'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '最新版本 v${update.latestVersion}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (update.releaseNotes.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(update.releaseNotes),
                ],
                const SizedBox(height: 12),
                Text(
                  '安装包大小 ${(update.packageSize / 1024 / 1024).toStringAsFixed(2)} MB',
                  style: const TextStyle(color: AppColors.secondaryText),
                ),
              ],
            ),
            actions: [
              if (!update.isMandatory)
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('稍后'),
                ),
              FilledButton(
                onPressed: () => _openUpdatePackage(update.packageUrl),
                child: const Text('下载更新'),
              ),
            ],
          ),
        ),
      );
    } catch (_) {
      // 更新检查不能影响 IM/OA、隧道和本地缓存启动。
    }
  }

  Future<void> _checkActiveInspection() async {
    try {
      final items = await ref.read(oaRepositoryProvider).activeInspections();
      if (!mounted) return;
      final pending = items
          .where(
            (item) =>
                item.responseStatus.toLowerCase() == 'pending' &&
                !_promptedInspectionIds.contains(item.inspectionId),
          )
          .firstOrNull;
      if (pending == null) return;
      _promptedInspectionIds.add(pending.inspectionId);
      await ref
          .read(oaRepositoryProvider)
          .markInspectionOpened(pending.inspectionId);
      if (!mounted) return;
      final status = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: Text(pending.title.isEmpty ? '在岗确认' : pending.title),
          content: pending.message.isEmpty ? null : Text(pending.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'unavailable'),
              child: const Text('暂时无法响应'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'present'),
              child: const Text('确认在岗'),
            ),
          ],
        ),
      );
      if (status == null) return;
      await ref
          .read(oaRepositoryProvider)
          .respondInspection(pending.inspectionId, status);
      ref.invalidate(oaActiveInspectionsProvider);
      if (mounted) _checkActiveInspection();
    } catch (_) {
      // 巡检暂时不可用时不阻断移动端主流程，下次回到前台会重试。
    }
  }

  Future<void> _openUpdatePackage(String packageUrl) async {
    final uri = Uri.tryParse(packageUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _synchronizeRuntime() async {
    try {
      await ref.read(tunnelControllerProvider.notifier).synchronize();
    } catch (_) {
      // A valid login session is not invalidated when tunnel synchronization
      // is temporarily unavailable.
    }
    if (!mounted) return;
    final tunnel = ref.read(tunnelControllerProvider).value;
    final session = ref.read(authControllerProvider).value;
    if (tunnel?.runtime != null && session != null) {
      await ref
          .read(managedBrowserSyncProvider.notifier)
          .synchronize(deviceId: session.deviceId, runtime: tunnel!.runtime!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bootstrapUnreadCount =
        ref
            .watch(imBootstrapProvider)
            .value
            ?.conversations
            .fold<int>(0, (total, item) => total + item.unreadCount) ??
        0;
    final badges = ref.watch(imBadgeSummaryProvider).value;
    final pendingApprovalCount =
        ref
            .watch(oaBootstrapProvider)
            .value
            ?.approvalRequests
            .where((item) => item.operableTask != null)
            .length ??
        0;
    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: MobileBottomNavigationBar(
        selectedIndex: widget.navigationShell.currentIndex,
        unreadCount: badges?.unreadMessages ?? bootstrapUnreadCount,
        pendingApprovalCount: pendingApprovalCount,
        pendingFriendRequestCount: badges?.pendingFriendRequests ?? 0,
        onDestinationSelected: (index) => widget.navigationShell.goBranch(
          index,
          initialLocation: index == widget.navigationShell.currentIndex,
        ),
      ),
    );
  }
}

class MobileBottomNavigationBar extends StatelessWidget {
  const MobileBottomNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    this.unreadCount = 0,
    this.pendingApprovalCount = 0,
    this.pendingFriendRequestCount = 0,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final int unreadCount;
  final int pendingApprovalCount;
  final int pendingFriendRequestCount;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      border: Border(
        top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
    ),
    child: NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: [
        const NavigationDestination(
          icon: Icon(TDIcons.app),
          selectedIcon: Icon(TDIcons.appFilled),
          label: '工作台',
        ),
        NavigationDestination(
          icon: Badge.count(
            count: unreadCount,
            isLabelVisible: unreadCount > 0,
            child: Icon(TDIcons.chatMessage),
          ),
          selectedIcon: Badge.count(
            count: unreadCount,
            isLabelVisible: unreadCount > 0,
            child: Icon(TDIcons.chatMessageFilled),
          ),
          label: '消息',
        ),
        NavigationDestination(
          icon: Badge.count(
            count: pendingApprovalCount,
            isLabelVisible: pendingApprovalCount > 0,
            child: const Icon(Icons.fact_check_outlined),
          ),
          selectedIcon: Badge.count(
            count: pendingApprovalCount,
            isLabelVisible: pendingApprovalCount > 0,
            child: const Icon(TDIcons.taskChecked),
          ),
          label: '待办',
        ),
        NavigationDestination(
          icon: Badge.count(
            count: pendingFriendRequestCount,
            isLabelVisible: pendingFriendRequestCount > 0,
            child: Icon(TDIcons.usergroup),
          ),
          selectedIcon: Badge.count(
            count: pendingFriendRequestCount,
            isLabelVisible: pendingFriendRequestCount > 0,
            child: Icon(TDIcons.usergroupFilled),
          ),
          label: '通讯录',
        ),
        NavigationDestination(
          icon: Icon(TDIcons.user),
          selectedIcon: Icon(TDIcons.userFilled),
          label: '我的',
        ),
      ],
    ),
  );
}
