import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/tdesign_icons.dart';
import '../../../shared/errors/mobile_error_text.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../../shared/widgets/page_states.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/domain/collaboration_models.dart';
import '../data/managed_sites_repository.dart';
import '../domain/app_catalog.dart';
import 'application_catalog_content.dart';

final mobileClockProvider = Provider<DateTime>((ref) => DateTime.now());

class WorkbenchPage extends ConsumerStatefulWidget {
  const WorkbenchPage({super.key});

  @override
  ConsumerState<WorkbenchPage> createState() => _WorkbenchPageState();
}

class _WorkbenchPageState extends ConsumerState<WorkbenchPage> {
  int _contentTab = 0;

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(oaBootstrapProvider);
    final syncAvailability = ref.watch(oaSyncAvailabilityProvider);
    final now = ref.watch(mobileClockProvider);
    return Scaffold(
      body: SafeArea(
        child: value.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => EmptyState(
            icon: TDIcons.cloud,
            title: '工作台加载失败',
            description: mobileErrorText(error),
            onRetry: () => ref.invalidate(oaBootstrapProvider),
          ),
          data: (data) {
            final pending = data.approvalRequests
                .where((item) => item.operableTask != null)
                .toList();
            final initiated = data.approvalRequests
                .where((item) => item.requesterId == data.currentMemberId)
                .toList();
            final unreadNotifications = data.notifications
                .where((item) => !item.isRead)
                .length;
            final todayItems = data.todos
                .where(
                  (item) => item.dueAt != null && _isSameDate(item.dueAt!, now),
                )
                .toList(growable: false);
            return RefreshIndicator(
              onRefresh: () async {
                await Future.wait([
                  ref.read(oaRepositoryProvider).refreshWorkspace(),
                  ref.read(imRepositoryProvider).refreshBootstrap(),
                ]);
                ref.invalidate(oaBootstrapProvider);
                ref.invalidate(oaApplicationCatalogProvider);
                ref.invalidate(oaNotificationsProvider);
                ref.invalidate(oaNotificationPageProvider);
                ref.invalidate(imBootstrapProvider);
              },
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                    sliver: SliverList.list(
                      children: [
                        _BrandHeader(
                          name: data.displayName,
                          now: now,
                          unreadNotifications: unreadNotifications,
                        ),
                        if (data.announcements.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _AnnouncementsPanel(item: data.announcements.first),
                        ],
                        const SizedBox(height: 8),
                        const _ApplicationsPanel(),
                        const SizedBox(height: 10),
                        _ActivityPanel(
                          selectedTab: _contentTab,
                          onTabChanged: (value) =>
                              setState(() => _contentTab = value),
                          pending: pending,
                          initiated: initiated,
                          syncAvailability: syncAvailability,
                        ),
                        if (todayItems.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          _SchedulePanel(items: todayItems),
                        ],
                        const SizedBox(height: 18),
                      ],
                    ),
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

class _BrandHeader extends StatelessWidget {
  const _BrandHeader({
    required this.name,
    required this.now,
    required this.unreadNotifications,
  });

  final String name;
  final DateTime now;
  final int unreadNotifications;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    key: const Key('workbench-brand-header'),
    constraints: const BoxConstraints(minHeight: 44),
    child: Row(
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_greeting(now)}${name.isEmpty ? '用户' : name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _dateLabel(now),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.secondaryText,
                ),
              ),
            ],
          ),
        ),
        Badge.count(
          count: unreadNotifications,
          isLabelVisible: unreadNotifications > 0,
          child: IconButton(
            tooltip: '通知',
            visualDensity: VisualDensity.compact,
            onPressed: () => context.push('/notifications'),
            icon: const Icon(TDIcons.notification, size: 20),
          ),
        ),
      ],
    ),
  );
}

String _greeting(DateTime now) {
  if (now.hour < 11) return '早上好，';
  if (now.hour < 14) return '中午好，';
  if (now.hour < 18) return '下午好，';
  return '晚上好，';
}

String _dateLabel(DateTime value) {
  const weekdays = ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'];
  return '${value.year}年${value.month}月${value.day}日 ${weekdays[value.weekday - 1]}';
}

bool _isSameDate(DateTime left, DateTime right) =>
    left.year == right.year &&
    left.month == right.month &&
    left.day == right.day;

class ManagedSitesPage extends ConsumerStatefulWidget {
  const ManagedSitesPage({super.key});

  @override
  ConsumerState<ManagedSitesPage> createState() => _ManagedSitesPageState();
}

class _ManagedSitesPageState extends ConsumerState<ManagedSitesPage> {
  String _query = '';

  Future<void> _refresh() async {
    final _ = await ref.refresh(managedSitesProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final sites = ref.watch(managedSitesProvider);
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: const Text('全部站点'),
        actions: [
          IconButton(
            tooltip: '刷新授权站点',
            visualDensity: VisualDensity.compact,
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: sites.when(
        loading: () => const ModuleLoadingState(label: '正在加载授权站点'),
        error: (error, _) => EmptyState(
          icon: TDIcons.cloud,
          title: error is ManagedSitesSessionExpired
              ? '登录已失效，请重新登录'
              : '授权站点加载失败',
          onRetry: () => ref.invalidate(managedSitesProvider),
        ),
        data: (items) {
          final keyword = _query.toLowerCase();
          final visibleItems = items
              .where((site) {
                return keyword.isEmpty ||
                    site.name.toLowerCase().contains(keyword) ||
                    site.category.toLowerCase().contains(keyword) ||
                    site.departmentName.toLowerCase().contains(keyword) ||
                    site.primaryDomain.toLowerCase().contains(keyword);
              })
              .toList(growable: false);
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 20),
              children: [
                MobileSearchField(
                  hintText: '搜索站点、部门或域名',
                  onChanged: (value) => setState(() => _query = value.trim()),
                ),
                const SizedBox(height: 8),
                if (visibleItems.isEmpty)
                  MobileSurface(
                    padding: const EdgeInsets.symmetric(vertical: 26),
                    child: Center(
                      child: Text(
                        items.isEmpty ? '当前账号暂无授权站点' : '暂无匹配站点',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.secondaryText,
                        ),
                      ),
                    ),
                  )
                else
                  MobileSurface(
                    child: Column(
                      children: [
                        for (final site in visibleItems)
                          _ManagedSiteRow(
                            site: site,
                            onTap: () => _openManagedSite(context, ref, site),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ManagedSiteRow extends StatelessWidget {
  const _ManagedSiteRow({required this.site, required this.onTap});

  final ManagedAccessSite site;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: ListTile(
      dense: true,
      minTileHeight: 50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: const Color(0xFFEAF2FF),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: const Icon(
          Icons.language_rounded,
          size: 18,
          color: AppColors.primary,
        ),
      ),
      title: Text(
        site.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        [
          site.departmentName,
          site.primaryDomain,
        ].where((value) => value.isNotEmpty).join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11, color: AppColors.secondaryText),
      ),
      trailing: const Icon(Icons.open_in_new_rounded, size: 17),
      onTap: onTap,
    ),
  );
}

Future<void> _openManagedSite(
  BuildContext context,
  WidgetRef ref,
  ManagedAccessSite site,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final resolution = await ref
        .read(managedSiteResolverProvider)
        .resolve(site);
    if (!context.mounted) return;
    final opened = await launchUrl(
      resolution.uri,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      messenger.showSnackBar(const SnackBar(content: Text('无法打开授权站点')));
    } else if (resolution.usedBackup && context.mounted) {
      messenger.showSnackBar(const SnackBar(content: Text('主地址不可用，已打开备用地址')));
    }
  } on ManagedSiteUnavailable catch (error) {
    if (context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text(mobileErrorText(error))));
    }
  }
}

// ignore: unused_element
class _CompactIdentity extends StatelessWidget {
  const _CompactIdentity({
    required this.name,
    required this.department,
    required this.pending,
    required this.initiated,
  });

  final String name;
  final String department;
  final int pending;
  final int initiated;

  @override
  Widget build(BuildContext context) => _SurfacePanel(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          InitialAvatar(name: name, radius: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (department.isNotEmpty)
                  Text(
                    department,
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.secondaryText,
                    ),
                  ),
              ],
            ),
          ),
          _MiniCount(value: pending, label: '待我处理'),
          const SizedBox(width: 16),
          _MiniCount(value: initiated, label: '我发起的'),
        ],
      ),
    ),
  );
}

class _MiniCount extends StatelessWidget {
  const _MiniCount({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        '$value',
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
      Text(
        label,
        style: const TextStyle(fontSize: 10.5, color: AppColors.secondaryText),
      ),
    ],
  );
}

// ignore: unused_element
class _IdentityPanel extends StatelessWidget {
  const _IdentityPanel({
    required this.name,
    required this.department,
    required this.now,
    required this.pending,
    required this.initiated,
    required this.copied,
    required this.participated,
  });

  final String name;
  final String department;
  final DateTime now;
  final int pending;
  final int initiated;
  final int copied;
  final int participated;

  @override
  Widget build(BuildContext context) {
    final displayName = name.isEmpty ? 'Codex 测试终端' : name;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  InitialAvatar(name: displayName, radius: 27),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: AppColors.success,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (department.isNotEmpty) department,
                        '${now.month}月${now.day}日 ${_weekday(now.weekday)}',
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
              const NetworkIndicator(size: 22),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .92),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _Metric(value: pending, label: '待我处理'),
                const _MetricDivider(),
                _Metric(value: initiated, label: '我发起的'),
                const _MetricDivider(),
                _Metric(value: copied, label: '抄送我的'),
                const _MetricDivider(),
                _Metric(value: participated, label: '我参与的'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _weekday(int value) =>
      const ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'][value - 1];
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: () => context.go('/todos'),
      borderRadius: BorderRadius.circular(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '$value',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.secondaryText,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MetricDivider extends StatelessWidget {
  const _MetricDivider();

  @override
  Widget build(BuildContext context) => const SizedBox(
    height: 28,
    child: VerticalDivider(color: Color(0xFFD8E2F0)),
  );
}

// ignore: unused_element
class _Announcement extends StatelessWidget {
  const _Announcement({required this.item});

  final OaAnnouncement item;

  @override
  Widget build(BuildContext context) => Container(
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: 14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF2E3),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(TDIcons.sound, size: 21, color: Color(0xFFED7B2F)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13.5, color: Color(0xFF8D3B12)),
          ),
        ),
        const Icon(TDIcons.chevronRight, size: 18, color: Color(0xFF8D3B12)),
      ],
    ),
  );
}

class _ApplicationsPanel extends StatelessWidget {
  const _ApplicationsPanel();

  @override
  Widget build(BuildContext context) {
    return _SurfacePanel(
      child: Column(
        children: [
          _SectionHeader(
            title: '常用应用',
            action: '全部应用',
            onTap: () => context.push('/apps'),
          ),
          ApplicationCatalogContent(
            builder: (applications) {
              final items = applications.take(9).toList();
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  childAspectRatio: 1.08,
                  mainAxisSpacing: 2,
                  crossAxisSpacing: 2,
                ),
                itemCount: items.length + 1,
                itemBuilder: (context, index) {
                  if (index == items.length) {
                    return _AppShortcut(
                      title: '更多',
                      icon: TDIcons.app,
                      color: const Color(0xFF5D667A),
                      onTap: () => context.push('/apps'),
                    );
                  }
                  final item = items[index];
                  return _AppShortcut(
                    title: item.title,
                    icon: item.icon,
                    application: item,
                    color: item.color,
                    onTap: item.route == null
                        ? null
                        : () => context.push(item.route!),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

class _AppShortcut extends StatelessWidget {
  const _AppShortcut({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
    this.application,
  });

  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;
  final MobileAppEntry? application;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: onTap == null ? .42 : 1,
    child: InkResponse(
      onTap: onTap,
      radius: 25,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: application == null
                ? Icon(icon, size: 18, color: Colors.white)
                : MobileAppIcon(
                    applicationKey: application!.applicationKey,
                    iconKey: application!.iconKey,
                    iconDataUrl: application!.iconDataUrl,
                    fallback: icon,
                    size: 20,
                    color: Colors.white,
                  ),
          ),
          const SizedBox(height: 3),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5),
          ),
        ],
      ),
    ),
  );
}

class _ActivityPanel extends StatelessWidget {
  const _ActivityPanel({
    required this.selectedTab,
    required this.onTabChanged,
    required this.pending,
    required this.initiated,
    required this.syncAvailability,
  });

  final int selectedTab;
  final ValueChanged<int> onTabChanged;
  final List<OaApprovalRequest> pending;
  final List<OaApprovalRequest> initiated;
  final OaSyncAvailability syncAvailability;

  @override
  Widget build(BuildContext context) {
    final labels = ['待我处理 ${pending.length}', '我发起的'];
    return _SurfacePanel(
      child: Column(
        children: [
          SizedBox(
            height: 43,
            child: Row(
              children: [
                for (var index = 0; index < labels.length; index++)
                  _PanelTab(
                    label: labels[index],
                    selected: selectedTab == index,
                    onTap: () => onTabChanged(index),
                  ),
                const Spacer(),
                if (syncAvailability == OaSyncAvailability.connecting)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.sync_rounded,
                          size: 15,
                          color: AppColors.secondaryText,
                        ),
                        SizedBox(width: 5),
                        Text(
                          '同步中',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppColors.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (syncAvailability == OaSyncAvailability.unavailable)
                  Semantics(
                    button: true,
                    label: '当前显示本机审批记录，查看全部',
                    child: ExcludeSemantics(
                      child: TextButton.icon(
                        key: const Key('workbench-approval-offline'),
                        onPressed: () => context.go('/todos'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(64, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 7),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.cloud_off_outlined, size: 15),
                        label: const Text(
                          '本机记录',
                          style: TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ),
                  )
                else
                  IconButton(
                    tooltip: '查看全部',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => context.go('/todos'),
                    icon: const Icon(TDIcons.filter, size: 18),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (selectedTab == 0)
            _ApprovalList(
              items: pending,
              actionable: true,
              syncAvailability: syncAvailability,
            )
          else
            _ApprovalList(
              items: initiated,
              actionable: false,
              syncAvailability: syncAvailability,
            ),
        ],
      ),
    );
  }
}

class _PanelTab extends StatelessWidget {
  const _PanelTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      height: 43,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: selected
            ? const Border(
                bottom: BorderSide(color: Color(0xFF0052D9), width: 2),
              )
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected
              ? Theme.of(context).brightness == Brightness.light
                    ? AppColors.text
                    : Theme.of(context).colorScheme.onSurface
              : Theme.of(context).brightness == Brightness.light
              ? AppColors.secondaryText
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );
}

class _ApprovalList extends StatelessWidget {
  const _ApprovalList({
    required this.items,
    required this.actionable,
    required this.syncAvailability,
  });

  final List<OaApprovalRequest> items;
  final bool actionable;
  final OaSyncAvailability syncAvailability;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      final connecting = syncAvailability == OaSyncAvailability.connecting;
      final offline = syncAvailability == OaSyncAvailability.unavailable;
      return _CompactEmpty(
        icon: connecting
            ? Icons.sync_rounded
            : offline
            ? Icons.cloud_off_outlined
            : TDIcons.taskChecked,
        title: connecting
            ? '正在同步审批'
            : offline
            ? '本机暂无审批记录'
            : '暂无审批事项',
      );
    }
    return Column(
      children: [
        for (var index = 0; index < items.take(3).length; index++) ...[
          if (index > 0) const Divider(height: 1, indent: 60, endIndent: 12),
          _ApprovalRow(request: items[index], actionable: actionable),
        ],
      ],
    );
  }
}

class _ApprovalRow extends StatelessWidget {
  const _ApprovalRow({required this.request, required this.actionable});

  final OaApprovalRequest request;
  final bool actionable;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: () => context.push('/approval/${request.id}'),
    child: Padding(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Icon(
              _tdIcon(request.templateName),
              size: 20,
              color: const Color(0xFF0052D9),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  request.title.isEmpty ? request.templateName : request.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    request.requesterName,
                    _formatTime(request.updatedAt ?? request.createdAt),
                  ].where((value) => value.isNotEmpty).join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ),
          ),
          if (actionable) ...[
            const SizedBox(width: 6),
            Semantics(
              button: true,
              label: '处理',
              excludeSemantics: true,
              child: SizedBox(
                key: ValueKey<String>(
                  'workbench-approval-action-${request.id}',
                ),
                width: 52,
                height: 28,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF2FF),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '处理',
                        style: TextStyle(
                          color: Color(0xFF0052D9),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      SizedBox(width: 1),
                      Icon(
                        TDIcons.chevronRight,
                        size: 14,
                        color: Color(0xFF0052D9),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ] else
            const Icon(
              TDIcons.chevronRight,
              size: 18,
              color: AppColors.weakText,
            ),
        ],
      ),
    ),
  );
}

// ignore: unused_element
class _NotificationList extends StatelessWidget {
  const _NotificationList({required this.items});

  final List<OaNotification> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _CompactEmpty(icon: TDIcons.notification, title: '暂无通知');
    }
    return Column(
      children: [
        for (var index = 0; index < items.take(3).length; index++) ...[
          if (index > 0) const Divider(height: 1, indent: 66, endIndent: 14),
          ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF2E3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                TDIcons.notification,
                size: 21,
                color: Color(0xFFED7B2F),
              ),
            ),
            title: Text(items[index].title, maxLines: 1),
            subtitle: Text(
              items[index].body,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: items[index].requestId.isEmpty
                ? () => context.push('/notifications')
                : () => context.push('/approval/${items[index].requestId}'),
          ),
        ],
      ],
    );
  }
}

// ignore: unused_element
class _RecentMessages extends StatelessWidget {
  const _RecentMessages({required this.conversations});

  final List<ImConversation> conversations;

  @override
  Widget build(BuildContext context) => _SurfacePanel(
    child: Column(
      children: [
        _SectionHeader(
          title: '最近消息',
          action: '全部',
          onTap: () => context.go('/messages'),
        ),
        for (var index = 0; index < conversations.length; index++) ...[
          if (index > 0) const Divider(height: 1, indent: 66, endIndent: 14),
          _ConversationRow(conversation: conversations[index]),
        ],
      ],
    ),
  );
}

class _SchedulePanel extends StatelessWidget {
  const _SchedulePanel({required this.items});

  final List<OaTodo> items;

  @override
  Widget build(BuildContext context) => _SurfacePanel(
    child: Column(
      children: [
        _SectionHeader(
          title: '今日日程',
          action: '全部',
          onTap: () => context.push('/schedule'),
        ),
        const Divider(height: 1),
        if (items.isEmpty)
          const _CompactEmpty(icon: TDIcons.calendarEvent, title: '今天暂无日程')
        else
          for (final item in items.take(3))
            Material(
              type: MaterialType.transparency,
              child: ListTile(
                dense: true,
                visualDensity: const VisualDensity(vertical: -3),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: Icon(
                  item.status == 'completed'
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 19,
                  color: item.status == 'completed'
                      ? AppColors.success
                      : AppColors.primary,
                ),
                title: Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                trailing: item.dueAt == null
                    ? null
                    : Text(
                        DateFormat('MM-dd HH:mm').format(item.dueAt!),
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.secondaryText,
                        ),
                      ),
                onTap: () => context.push('/schedule'),
              ),
            ),
      ],
    ),
  );
}

class _AnnouncementsPanel extends StatelessWidget {
  const _AnnouncementsPanel({required this.item});

  final OaAnnouncement item;

  @override
  Widget build(BuildContext context) => _SurfacePanel(
    child: Material(
      type: MaterialType.transparency,
      child: ListTile(
        dense: true,
        minTileHeight: 44,
        visualDensity: const VisualDensity(vertical: -4),
        contentPadding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
        leading: const Icon(TDIcons.sound, size: 19, color: Color(0xFFED7B2F)),
        title: Text(
          item.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        trailing: const Icon(TDIcons.chevronRight, size: 17),
        onTap: () => context.push('/notifications?tab=announcements'),
      ),
    ),
  );
}

class _ConversationRow extends StatelessWidget {
  const _ConversationRow({required this.conversation});

  final ImConversation conversation;

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: ListTile(
      dense: true,
      contentPadding: const EdgeInsets.fromLTRB(12, 0, 10, 0),
      leading: InitialAvatar(name: conversation.title, radius: 20),
      title: Text(
        conversation.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        conversation.preview.isEmpty ? '暂无消息' : conversation.preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11.5),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatTime(conversation.updatedAt),
            style: const TextStyle(fontSize: 10.5, color: AppColors.weakText),
          ),
          if (conversation.unreadCount > 0) ...[
            const SizedBox(height: 3),
            Badge.count(count: conversation.unreadCount),
          ],
        ],
      ),
      onTap: () => context.push('/chat/${conversation.id}'),
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.action, this.onTap});

  final String title;
  final String action;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 38,
    child: Row(
      children: [
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        if (action.isNotEmpty)
          TextButton(
            onPressed: onTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(action, style: const TextStyle(fontSize: 12)),
                const Icon(TDIcons.chevronRight, size: 15),
              ],
            ),
          ),
        const SizedBox(width: 3),
      ],
    ),
  );
}

class _SurfacePanel extends StatelessWidget {
  const _SurfacePanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(10),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0A1D2433),
          blurRadius: 12,
          offset: Offset(0, 3),
        ),
      ],
    ),
    child: ClipRRect(borderRadius: BorderRadius.circular(10), child: child),
  );
}

class _CompactEmpty extends StatelessWidget {
  const _CompactEmpty({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 54,
    child: Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 20, color: AppColors.weakText),
        const SizedBox(width: 9),
        Text(
          title,
          style: const TextStyle(fontSize: 12, color: AppColors.secondaryText),
        ),
      ],
    ),
  );
}

IconData _tdIcon(String rawTitle) {
  final title = rawTitle.toLowerCase();
  if (title.contains('打卡') || title.contains('考勤')) {
    return TDIcons.calendarEdit;
  }
  if (title.contains('请假')) return TDIcons.userTime;
  if (title.contains('加班')) return TDIcons.time;
  if (title.contains('出差')) return TDIcons.work;
  if (title.contains('报销') || title.contains('请款')) return TDIcons.money;
  if (title.contains('补卡')) return TDIcons.calendarEvent;
  if (title.contains('用印')) return TDIcons.fileSafety;
  if (title.contains('采购')) return TDIcons.cart;
  return TDIcons.file1;
}

String _formatTime(DateTime? value) {
  if (value == null) return '';
  final now = DateTime.now();
  if (value.year == now.year &&
      value.month == now.month &&
      value.day == now.day) {
    return DateFormat('HH:mm').format(value);
  }
  return DateFormat('MM-dd').format(value);
}
