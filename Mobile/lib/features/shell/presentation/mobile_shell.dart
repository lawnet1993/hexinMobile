import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../attendance/presentation/inspection_response_sheet.dart';
import '../../../core/theme/tdesign_icons.dart';
import '../../../core/diagnostics/mobile_startup_diagnostics.dart';
import '../../../core/notifications/mobile_push_registration.dart';
import '../../../core/updates/client_update_repository.dart';
import '../../../core/updates/client_update_sheet.dart';
import '../../../core/security/managed_security_repository.dart';
import '../../auth/application/auth_controller.dart';
import '../../collaboration/application/im_sync_coordinator.dart';
import '../../collaboration/application/mobile_device_authorization_coordinator.dart';
import '../../collaboration/application/mobile_presence_coordinator.dart';
import '../../collaboration/application/oa_catalog_sync_coordinator.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/domain/collaboration_models.dart';

@visibleForTesting
int mobilePendingWorkCount(OaBootstrap? data) {
  if (data == null) return 0;
  return data.todos.where((item) => !isTerminalTodoStatus(item.status)).length +
      data.approvalRequests.where((item) => item.operableTask != null).length;
}

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
  bool _sessionRuntimeStopped = false;
  bool _notificationPermissionChecked = false;

  @override
  void initState() {
    super.initState();
    MobileStartupDiagnostics.markCurrent(MobileStartupStage.shellCreated);
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
    ref.listenManual(authControllerProvider, (previous, next) {
      if (previous?.value != null && next.value == null) {
        _stopSessionRuntime();
      } else if (!_sessionRuntimeStopped &&
          previous?.value != null &&
          next.value != null &&
          !previous!.value!.isSameSession(next.value!)) {
        // A refreshed login token must bind push registration to that session.
        _pushRegistration.synchronize().ignore();
      }
    });
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      MobileStartupDiagnostics.markCurrent(MobileStartupStage.shellFirstFrame);
      ref
          .read(imRealtimeAvailabilityControllerProvider.notifier)
          .markConnecting();
      MobileStartupDiagnostics.markCurrent(
        MobileStartupStage.collaborationSyncRequested,
      );
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
    if (!mounted || _sessionRuntimeStopped) return;
    await Future.wait([
      _presenceCoordinator.start(),
      _imSyncCoordinator.start(),
      _oaSyncCoordinator.start(),
    ]);
    if (!mounted || _sessionRuntimeStopped) return;
    try {
      await _pushRegistration.start(onOpenRoute: _openPushRoute);
    } catch (_) {
      // Push registration must not block local cache and foreground sync.
    }
    if (!mounted || _sessionRuntimeStopped) return;
    await _requestNotificationPermissionIfNeeded();
  }

  Future<void> _requestNotificationPermissionIfNeeded() async {
    if (_notificationPermissionChecked) return;
    _notificationPermissionChecked = true;
    try {
      await requestMobileNotificationPermissionIfNeeded(
        ref.read(mobileNotificationPermissionSourceProvider),
      );
      if (mounted) {
        ref.invalidate(mobileNotificationPermissionStateProvider);
      }
    } catch (_) {
      // A denied or unavailable system permission must not block IM/OA startup.
    }
  }

  Future<void> _openPushRoute(String route) async {
    if (!mounted || _sessionRuntimeStopped) return;
    await _imSyncCoordinator.synchronizeNowAndWait(
      reconcileConversations: true,
    );
    if (!mounted || _sessionRuntimeStopped) return;
    context.go(route);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopSessionRuntime();
    super.dispose();
  }

  void _stopSessionRuntime() {
    if (_sessionRuntimeStopped) return;
    _sessionRuntimeStopped = true;
    _pushRegistration.stop();
    _presenceCoordinator.stop();
    _imSyncCoordinator.stop();
    _oaSyncCoordinator.stop();
    _terminalCommandCoordinator.stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_sessionRuntimeStopped) return;
      _imSyncCoordinator.synchronizeNow(reconcileConversations: true);
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
      await showClientUpdateSheet(
        context,
        info: update,
        onDownload: () => _openUpdatePackage(update.packageUrl),
      );
    } catch (_) {
      // 更新检查不能影响 IM/OA 和本地缓存启动。
    }
  }

  Future<void> _checkActiveInspection() async {
    await showActiveInspectionPrompt(
      context: context,
      ref: ref,
      promptedIds: _promptedInspectionIds,
    );
  }

  Future<void> _openUpdatePackage(String packageUrl) async {
    final uri = Uri.tryParse(packageUrl);
    if (uri == null || !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('更新地址无效，请联系管理员')));
      }
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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
    final pendingWorkCount = mobilePendingWorkCount(
      ref.watch(oaBootstrapProvider).value,
    );
    return Scaffold(
      body: widget.navigationShell,
      bottomNavigationBar: MobileBottomNavigationBar(
        selectedIndex: widget.navigationShell.currentIndex,
        unreadCount: badges?.unreadMessages ?? bootstrapUnreadCount,
        pendingWorkCount: pendingWorkCount,
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
    this.pendingWorkCount = 0,
    this.pendingFriendRequestCount = 0,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final int unreadCount;
  final int pendingWorkCount;
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
            count: pendingWorkCount,
            isLabelVisible: pendingWorkCount > 0,
            child: const Icon(Icons.fact_check_outlined),
          ),
          selectedIcon: Badge.count(
            count: pendingWorkCount,
            isLabelVisible: pendingWorkCount > 0,
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
