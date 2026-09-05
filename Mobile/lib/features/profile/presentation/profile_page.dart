import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/storage/secure_session_store.dart';
import '../../../shared/widgets/mobile_bottom_sheets.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../auth/application/auth_controller.dart';
import '../../collaboration/application/mobile_device_authorization_coordinator.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/data/im_member_presence.dart';
import '../../collaboration/domain/collaboration_models.dart';

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider).value;
    final member = ref.watch(imBootstrapProvider).value?.currentMember;
    final realtimeAvailability = ref.watch(imRealtimeAvailabilityProvider);
    final presenceAvailable =
        realtimeAvailability == ImRealtimeAvailability.available;
    final devices = ref.watch(imDeviceAuthorizationsProvider);
    final currentDevice = ref.watch(currentMobileDeviceAuthorizationProvider);
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.light;
    final language = ref.watch(imLanguagePreferenceProvider).value?.language;
    final name = _profileDisplayName(member, session);
    final avatarName = name == '个人资料' ? '我' : name;
    final department = member?.departmentName.trim() ?? '';
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 6, 12, 16),
          children: [
            const EnterprisePageHeader(title: '我的'),
            MobileSurface(
              key: const Key('profile-summary-card'),
              padding: EdgeInsets.zero,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: member == null && session == null
                    ? null
                    : () => context.push('/profile/edit'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                  child: Row(
                    children: [
                      InitialAvatar(
                        name: avatarName,
                        radius: 20,
                        online: watchMemberPresence(
                          ref,
                          member,
                          transportAvailable: presenceAvailable,
                        ).online,
                        avatarKey: member?.avatarKey ?? '',
                        avatarDataUrl: member?.avatarDataUrl ?? '',
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (department.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                department,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.secondaryText,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: AppColors.weakText,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            _SettingsGroup(
              children: [
                _Entry(
                  icon: Icons.admin_panel_settings_outlined,
                  title: '账户与安全',
                  onTap: () => context.push('/account-security'),
                ),
                _Entry(
                  icon: Icons.notifications_none_rounded,
                  title: '通知设置',
                  subtitle: '消息、审批与公告',
                  onTap: () => context.push('/notification-settings'),
                ),
                _Entry(
                  icon: Icons.devices_outlined,
                  title: '登录设备',
                  subtitle: deviceAuthorizationSummary(
                    devices,
                    currentDeviceId: session?.deviceId ?? '',
                    currentDevice: currentDevice,
                    syncState: realtimeAvailability,
                  ),
                  onTap: () => context.push('/login-devices'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _SettingsGroup(
              children: [
                _Entry(
                  icon: Icons.palette_outlined,
                  title: '外观与语言',
                  subtitle:
                      '${switch (themeMode) {
                        ThemeMode.light => '浅色',
                        ThemeMode.dark => '深色',
                        ThemeMode.system => '跟随系统',
                      }}·${switch (language) {
                        'zh-TW' => '繁體中文',
                        'en-US' => 'English',
                        _ => '简体中文',
                      }}',
                  onTap: () => context.push('/appearance-language'),
                ),
                _Entry(
                  icon: Icons.help_outline_rounded,
                  title: '帮助与反馈',
                  onTap: () => context.push('/help-feedback'),
                ),
                _Entry(
                  icon: Icons.info_outline_rounded,
                  title: '关于合兴智联',
                  subtitle: 'v1.0.1',
                  onTap: () => context.push('/about'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            MobileSurface(
              key: const Key('profile-logout-entry'),
              padding: EdgeInsets.zero,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => _logout(context, ref),
                child: const SizedBox(
                  height: 42,
                  child: Center(
                    child: Text(
                      '退出登录',
                      style: TextStyle(fontSize: 13.5, color: AppColors.error),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showMobileConfirmSheet(
      context,
      title: '退出登录',
      message: '退出后需要重新验证终端账号。',
      confirmLabel: '退出',
      destructive: true,
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }
}

String _profileDisplayName(ImMember? member, MobileSession? session) {
  final memberName = member?.displayName.trim() ?? '';
  if (memberName.isNotEmpty) return memberName;
  final sessionName = session?.displayName.trim() ?? '';
  final username = session?.username.trim() ?? '';
  if (sessionName.isNotEmpty &&
      sessionName.toLowerCase() != username.toLowerCase()) {
    return sessionName;
  }
  return '个人资料';
}

String deviceAuthorizationSummary(
  AsyncValue<List<ImDeviceAuthorization>> value, {
  required String currentDeviceId,
  ImDeviceAuthorization? currentDevice,
  ImRealtimeAvailability syncState = ImRealtimeAvailability.available,
}) {
  if (currentDevice != null) return _deviceAuthorizationLabel(currentDevice);
  if (value.isLoading) {
    return syncState == ImRealtimeAvailability.unavailable
        ? '暂时无法同步'
        : '正在同步设备';
  }
  if (value.hasError) {
    return switch (syncState) {
      ImRealtimeAvailability.connecting => '正在同步设备',
      ImRealtimeAvailability.unavailable => '暂时无法同步',
      ImRealtimeAvailability.available => '设备状态同步失败',
    };
  }
  final devices = value.value ?? const <ImDeviceAuthorization>[];
  final normalizedCurrentDeviceId = currentDeviceId.trim().toLowerCase();
  ImDeviceAuthorization? current;
  for (final item in devices) {
    if (normalizedCurrentDeviceId.isNotEmpty &&
        item.deviceId.trim().toLowerCase() == normalizedCurrentDeviceId) {
      current = item;
      break;
    }
  }
  if (current == null) {
    return switch (syncState) {
      ImRealtimeAvailability.connecting => '正在同步设备',
      ImRealtimeAvailability.unavailable => '暂时无法同步',
      ImRealtimeAvailability.available => '未登记当前设备',
    };
  }
  return _deviceAuthorizationLabel(current);
}

String _deviceAuthorizationLabel(ImDeviceAuthorization current) {
  final name = current.deviceName.trim();
  final platform = current.platform.trim();
  return [
    if (name.isNotEmpty) name,
    if (platform.isNotEmpty) platform,
  ].join(' · ');
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => MobileSurface(
    child: Column(
      children: [
        for (var index = 0; index < children.length; index++) ...[
          children[index],
          if (index < children.length - 1)
            const Divider(height: 1, indent: 48, endIndent: 12),
        ],
      ],
    ),
  );
}

class _Entry extends StatelessWidget {
  const _Entry({
    required this.icon,
    required this.title,
    this.onTap,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    minTileHeight: 42,
    dense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12),
    leading: Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(6),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: AppColors.primary, size: 14.5),
    ),
    title: Text(
      title,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
    ),
    subtitle: subtitle == null
        ? null
        : Text(
            subtitle!,
            style: const TextStyle(
              fontSize: 10.5,
              color: AppColors.secondaryText,
            ),
          ),
    trailing: const Icon(
      Icons.chevron_right_rounded,
      size: 19,
      color: AppColors.weakText,
    ),
    onTap: onTap,
  );
}
