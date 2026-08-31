import 'package:dio/dio.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../core/notifications/mobile_push_registration.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/updates/client_update_repository.dart';
import '../../auth/application/auth_controller.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/domain/collaboration_models.dart';
import '../../network/application/tunnel_controller.dart';

class AccountSecurityPage extends ConsumerStatefulWidget {
  const AccountSecurityPage({super.key});

  @override
  ConsumerState<AccountSecurityPage> createState() =>
      _AccountSecurityPageState();
}

class _AccountSecurityPageState extends ConsumerState<AccountSecurityPage> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _submitting = false;
  bool _obscure = true;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).value;
    final member = ref.watch(imBootstrapProvider).value?.currentMember;
    return _SettingsScaffold(
      title: '账户与安全',
      children: [
        _SettingsSection(
          title: '终端账户',
          children: [
            _ValueRow(label: '账号', value: session?.username ?? '-'),
            _ValueRow(label: '设备 ID', value: _shortId(session?.deviceId)),
            _ValueRow(
              label: '当前状态',
              value: session == null
                  ? '会话已失效'
                  : member?.isOnline == true
                  ? '已验证·在线'
                  : '已验证·离线',
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SettingsSection(
          title: '修改登录密码',
          child: Form(
            key: _formKey,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Column(
                children: [
                  _PasswordField(
                    controller: _current,
                    label: '当前密码',
                    obscure: _obscure,
                  ),
                  const SizedBox(height: 10),
                  _PasswordField(
                    controller: _next,
                    label: '新密码',
                    obscure: _obscure,
                    validateLength: true,
                  ),
                  const SizedBox(height: 10),
                  _PasswordField(
                    controller: _confirm,
                    label: '再次输入新密码',
                    obscure: _obscure,
                    confirm: _next,
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setState(() => _obscure = !_obscure),
                      child: Text(_obscure ? '显示密码' : '隐藏密码'),
                    ),
                  ),
                  FilledButton(
                    onPressed: _submitting ? null : _changePassword,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(38),
                    ),
                    child: Text(_submitting ? '提交中…' : '确认修改'),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '修改成功后当前会话将退出，需使用新密码重新登录。',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _changePassword() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final session = ref.read(authControllerProvider).value;
    if (session == null) return;
    setState(() => _submitting = true);
    try {
      await ref
          .read(dioProvider)
          .post<void>(
            '/api/client/change-password',
            data: {
              'deviceId': session.deviceId,
              'currentPassword': _current.text,
              'newPassword': _next.text,
            },
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('密码已修改，请重新登录')));
      await ref
          .read(authControllerProvider.notifier)
          .logout(clearCredential: true);
    } on DioException catch (error) {
      if (!mounted) return;
      final data = error.response?.data;
      final message = data is Map
          ? (data['message'] ?? data['error'])?.toString()
          : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message?.isNotEmpty == true ? message! : '密码修改失败'),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

class NotificationSettingsPage extends ConsumerStatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  ConsumerState<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState
    extends ConsumerState<NotificationSettingsPage> {
  bool _saving = false;

  Future<void> _updatePrivacy(String mode) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final synchronized = await ref
          .read(mobilePushRegistrationProvider)
          .synchronize(privacyMode: mode);
      if (!synchronized) {
        throw StateError('当前安装包尚未取得推送令牌');
      }
      ref.invalidate(imPushDeviceProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('推送设置已同步')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('设置失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pushDevice = ref.watch(imPushDeviceProvider);
    final runtimeToken = ref.watch(mobilePushRuntimeTokenProvider);
    return _SettingsScaffold(
      title: '消息通知',
      children: [
        _SettingsSection(
          title: '移动推送',
          child: pushDevice.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(22),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Text('推送状态加载失败：$error'),
                  TextButton(
                    onPressed: () => ref.invalidate(imPushDeviceProvider),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
            data: (device) => runtimeToken.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(22),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => const _PushUnavailableTile(),
              data: (token) => device == null || token == null
                  ? const _PushUnavailableTile()
                  : Column(
                      children: [
                        _ValueRow(
                          label: '推送状态',
                          value: device.isEnabled ? '已启用' : '已停用',
                        ),
                        const Divider(height: 1, indent: 14),
                        _ChoiceRow(
                          label: '锁屏内容',
                          value: _privacyLabel(device.privacyMode),
                          values: const ['仅显示摘要', '显示消息详情', '不显示内容'],
                          onSelected: _saving
                              ? (_) {}
                              : (value) => _updatePrivacy(_privacyMode(value)),
                        ),
                        const Divider(height: 1, indent: 14),
                        _ValueRow(
                          label: '推送通道',
                          value: '${token.platform} · ${token.provider}',
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PushUnavailableTile extends StatelessWidget {
  const _PushUnavailableTile();

  @override
  Widget build(BuildContext context) => const ListTile(
    dense: true,
    minTileHeight: 64,
    leading: Icon(Icons.notifications_off_outlined),
    title: Text('当前设备未注册推送服务'),
    subtitle: Text('打开应用后会自动同步消息和 OA 通知'),
  );
}

String _privacyLabel(String mode) => switch (mode) {
  'detail' => '显示消息详情',
  'none' => '不显示内容',
  _ => '仅显示摘要',
};

String _privacyMode(String label) => switch (label) {
  '显示消息详情' => 'detail',
  '不显示内容' => 'none',
  _ => 'summary',
};

class LoginDevicesPage extends ConsumerStatefulWidget {
  const LoginDevicesPage({super.key});

  @override
  ConsumerState<LoginDevicesPage> createState() => _LoginDevicesPageState();
}

class _LoginDevicesPageState extends ConsumerState<LoginDevicesPage> {
  bool _registering = false;
  String? _revokingId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _registerCurrent(silent: true);
    });
  }

  Future<void> _registerCurrent({bool silent = false}) async {
    if (_registering) return;
    setState(() => _registering = true);
    try {
      final info = await DeviceInfoPlugin().androidInfo;
      final rawName = [
        info.brand,
        info.model,
      ].where((value) => value.trim().isNotEmpty).join(' ');
      final lowerName = rawName.toLowerCase();
      final name =
          lowerName.contains('sdk_gphone') || lowerName.contains('generic_x86')
          ? 'Android 模拟器'
          : rawName;
      await ref
          .read(imRepositoryProvider)
          .registerDeviceAuthorization(
            deviceName: name.isEmpty ? 'Android 移动端' : name,
          );
      ref.invalidate(imDeviceAuthorizationsProvider);
    } catch (error) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('设备授权失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  Future<void> _revoke(ImDeviceAuthorization device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('撤销设备授权'),
        content: Text('撤销“${device.deviceName}”后，该设备需要重新登录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('撤销'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _revokingId = device.deviceId);
    try {
      await ref
          .read(imRepositoryProvider)
          .revokeDeviceAuthorization(device.deviceId);
      ref.invalidate(imDeviceAuthorizationsProvider);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('撤销失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _revokingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).value;
    final devices = ref.watch(imDeviceAuthorizationsProvider);
    return _SettingsScaffold(
      title: '登录设备',
      children: [
        _SettingsSection(
          title: '已授权设备',
          child: devices.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  Text('设备列表加载失败：$error'),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(imDeviceAuthorizationsProvider),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
            data: (items) => items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: SizedBox(
                        height: 40,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            textStyle: const TextStyle(fontSize: 13.5),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: _registering
                              ? null
                              : () => _registerCurrent(),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: Text(_registering ? '授权中…' : '授权当前设备'),
                        ),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < items.length; i++) ...[
                        _DeviceAuthorizationTile(
                          device: items[i],
                          currentDeviceId: session?.deviceId ?? '',
                          revoking: _revokingId == items[i].deviceId,
                          onRevoke: () => _revoke(items[i]),
                        ),
                        if (i < items.length - 1)
                          const Divider(height: 1, indent: 58),
                      ],
                    ],
                  ),
          ),
        ),
      ],
    );
  }
}

class _DeviceAuthorizationTile extends StatelessWidget {
  const _DeviceAuthorizationTile({
    required this.device,
    required this.currentDeviceId,
    required this.revoking,
    required this.onRevoke,
  });

  final ImDeviceAuthorization device;
  final String currentDeviceId;
  final bool revoking;
  final VoidCallback onRevoke;

  @override
  Widget build(BuildContext context) {
    final isCurrent =
        currentDeviceId.isNotEmpty &&
        currentDeviceId.toLowerCase() == device.deviceId.toLowerCase();
    final lastSeen = device.lastSeenAt == null
        ? '暂无活动记录'
        : '最近活动 ${device.lastSeenAt!.toLocal().toString().substring(0, 16)}';
    return ListTile(
      dense: true,
      minTileHeight: 54,
      leading: Icon(
        device.platform.toLowerCase().contains('android')
            ? Icons.phone_android_rounded
            : Icons.computer_rounded,
        size: 21,
        color: device.isAuthorized ? AppColors.primary : AppColors.weakText,
      ),
      title: Text(
        device.deviceName.isEmpty ? device.platform : device.deviceName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${device.platform} · $lastSeen',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11),
      ),
      trailing: isCurrent
          ? const Text('当前', style: TextStyle(color: AppColors.success))
          : device.isAuthorized
          ? TextButton(
              onPressed: revoking ? null : onRevoke,
              child: Text(revoking ? '撤销中…' : '撤销'),
            )
          : const Text('已撤销', style: TextStyle(color: AppColors.secondaryText)),
    );
  }
}

class AppearanceLanguagePage extends ConsumerStatefulWidget {
  const AppearanceLanguagePage({super.key});

  @override
  ConsumerState<AppearanceLanguagePage> createState() =>
      _AppearanceLanguagePageState();
}

class _AppearanceLanguagePageState
    extends ConsumerState<AppearanceLanguagePage> {
  bool _saving = false;

  Future<void> _updateTheme(String label) async {
    final mode = switch (label) {
      '浅色' => ThemeMode.light,
      '深色' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    try {
      await ref.read(themeModeProvider.notifier).setThemeMode(mode);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('主题保存失败：$error')));
      }
    }
  }

  Future<void> _updateLanguage(String label) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await ref.read(imRepositoryProvider).updateLanguage(_languageCode(label));
      ref.invalidate(imLanguagePreferenceProvider);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('账号语言已更新')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('语言更新失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(imLanguagePreferenceProvider);
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.light;
    return _SettingsScaffold(
      title: '外观与语言',
      children: [
        _SettingsSection(
          title: '界面设置',
          children: [
            _ChoiceRow(
              label: '主题模式',
              value: switch (themeMode) {
                ThemeMode.light => '浅色',
                ThemeMode.dark => '深色',
                ThemeMode.system => '跟随系统',
              },
              values: const ['跟随系统', '浅色', '深色'],
              onSelected: _updateTheme,
            ),
            language.when(
              loading: () => const _ValueRow(label: '账号语言', value: '同步中…'),
              error: (_, _) => _ValueRow(
                label: '账号语言',
                value: '同步失败',
                onTap: () => ref.invalidate(imLanguagePreferenceProvider),
              ),
              data: (preference) => _ChoiceRow(
                label: '账号语言',
                value: _saving ? '同步中…' : _languageLabel(preference?.language),
                values: _saving
                    ? const ['同步中…']
                    : const ['简体中文', '繁體中文', 'English'],
                onSelected: _updateLanguage,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

String _languageLabel(String? language) => switch (language) {
  'zh-TW' => '繁體中文',
  'en-US' => 'English',
  _ => '简体中文',
};

String _languageCode(String label) => switch (label) {
  '繁體中文' => 'zh-TW',
  'English' => 'en-US',
  _ => 'zh-CN',
};

class HelpFeedbackPage extends ConsumerWidget {
  const HelpFeedbackPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => _SettingsScaffold(
    title: '帮助与反馈',
    children: const [
      _SettingsSection(
        title: '常见问题',
        children: [
          ExpansionTile(
            title: Text('无法收到消息提醒'),
            childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 14),
            children: [Text('请确认系统通知权限已开启，并在“消息通知”中启用对应提醒。')],
          ),
          ExpansionTile(
            title: Text('审批数据没有更新'),
            childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 14),
            children: [Text('在页面顶部下拉刷新；离线数据会在网络恢复后自动同步。')],
          ),
          ExpansionTile(
            title: Text('无法访问授权站点'),
            childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 14),
            children: [Text('请先在“网络与安全”中检查管理通道和策略状态。')],
          ),
        ],
      ),
      SizedBox(height: 12),
      _SettingsSection(
        title: '反馈渠道',
        children: [_ValueRow(label: '联系方式', value: '请联系企业管理员')],
      ),
      SizedBox(height: 8),
      _DiagnosticsAction(),
    ],
  );
}

class _DiagnosticsAction extends ConsumerWidget {
  const _DiagnosticsAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Align(
    alignment: Alignment.centerLeft,
    child: OutlinedButton.icon(
      onPressed: () => _copy(context, ref),
      icon: const Icon(Icons.copy_all_outlined, size: 17),
      label: const Text('复制诊断信息'),
    ),
  );

  Future<void> _copy(BuildContext context, WidgetRef ref) async {
    final package = await PackageInfo.fromPlatform();
    final device = await DeviceInfoPlugin().deviceInfo;
    final tunnel = ref.read(tunnelControllerProvider).value;
    final text = [
      '应用: ${package.appName} ${package.version} (${package.buildNumber})',
      '设备: ${device.data['brand'] ?? ''} ${device.data['model'] ?? ''}'.trim(),
      '系统: ${device.data['version.release'] ?? device.data['systemVersion'] ?? ''}',
      '安全连接: ${tunnel?.status.phase.name ?? 'checking'}',
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('诊断信息已复制')));
    }
  }
}

class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  AsyncValue<ClientUpdateInfo>? _update;

  Future<void> _checkUpdate() async {
    if (_update?.isLoading == true) return;
    setState(() => _update = const AsyncLoading());
    try {
      final info = await ref.refresh(clientUpdateInfoProvider.future);
      if (mounted) setState(() => _update = AsyncData(info));
    } catch (error, stackTrace) {
      if (mounted) setState(() => _update = AsyncError(error, stackTrace));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
    future: PackageInfo.fromPlatform(),
    builder: (context, snapshot) => _SettingsScaffold(
      title: '关于合兴智联',
      children: [
        const SizedBox(height: 16),
        const Icon(Icons.shield_rounded, size: 58, color: AppColors.primary),
        const SizedBox(height: 10),
        const Center(
          child: Text(
            '合兴智联',
            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(height: 4),
        const Center(
          child: Text(
            '安全访问 · 高效协同',
            style: TextStyle(color: AppColors.secondaryText),
          ),
        ),
        const SizedBox(height: 24),
        _SettingsSection(
          children: [
            _ValueRow(label: '版本', value: snapshot.data?.version ?? '获取中'),
            _ValueRow(
              label: '检查更新',
              value: _update == null
                  ? '点击检查'
                  : _update!.when(
                      loading: () => '检查中…',
                      error: (_, _) => '检查失败，点击重试',
                      data: (info) => !info.hasPublishedVersion
                          ? '暂无发布版本'
                          : info.updateAvailable
                          ? '发现 v${info.latestVersion}'
                          : '已是最新版本',
                    ),
              onTap: _update?.isLoading == true
                  ? null
                  : () {
                      final info = _update?.value;
                      if (info?.updateAvailable == true) {
                        _showClientUpdate(context, info!);
                      } else {
                        _checkUpdate();
                      }
                    },
            ),
            const _ValueRow(label: '平台', value: 'Android'),
            const _ValueRow(label: '安全策略', value: '由管理平台统一下发'),
          ],
        ),
        const SizedBox(height: 18),
        const Center(
          child: Text(
            '© 2026 合兴智联',
            style: TextStyle(fontSize: 11.5, color: AppColors.secondaryText),
          ),
        ),
      ],
    ),
  );
}

Future<void> _showClientUpdate(
  BuildContext context,
  ClientUpdateInfo info,
) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(info.isMandatory ? '必须更新客户端' : '发现新版本'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '最新版本 v${info.latestVersion}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (info.releaseNotes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(info.releaseNotes),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            final uri = Uri.tryParse(info.packageUrl);
            if (uri == null ||
                !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('更新地址无效，请联系管理员')));
              return;
            }
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          },
          child: const Text('下载更新'),
        ),
      ],
    ),
  );
}

class _SettingsScaffold extends StatelessWidget {
  const _SettingsScaffold({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), centerTitle: true),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: children,
    ),
  );
}

class _SettingsSection extends StatelessWidget {
  const _SettingsSection({this.title, this.child, this.children = const []});
  final String? title;
  final Widget? child;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (title != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 7),
          child: Text(
            title!,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      Material(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child:
            child ??
            Column(
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1)
                    const Divider(height: 1, indent: 14),
                ],
              ],
            ),
      ),
    ],
  );
}

class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value, this.onTap});
  final String label;
  final String value;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    minTileHeight: 48,
    title: Text(label, style: const TextStyle(fontSize: 14)),
    trailing: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 210),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12.5,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    ),
    onTap: onTap,
  );
}

class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.value,
    required this.values,
    required this.onSelected,
  });
  final String label;
  final String value;
  final List<String> values;
  final ValueChanged<String> onSelected;

  Future<void> _openChoices(BuildContext context) async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              for (final item in values)
                ListTile(
                  dense: true,
                  minTileHeight: 48,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(item, style: const TextStyle(fontSize: 14)),
                  trailing: item == value
                      ? const Icon(
                          Icons.check_rounded,
                          size: 20,
                          color: AppColors.primary,
                        )
                      : null,
                  onTap: () => Navigator.pop(context, item),
                ),
            ],
          ),
        ),
      ),
    );
    if (selected != null && selected != value) onSelected(selected);
  }

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    minTileHeight: 50,
    title: Text(label, style: const TextStyle(fontSize: 14)),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: const TextStyle(fontSize: 13, color: AppColors.secondaryText),
        ),
        const SizedBox(width: 4),
        const Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: AppColors.weakText,
        ),
      ],
    ),
    onTap: () => _openChoices(context),
  );
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.obscure,
    this.validateLength = false,
    this.confirm,
  });
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final bool validateLength;
  final TextEditingController? confirm;
  @override
  Widget build(BuildContext context) => TextFormField(
    controller: controller,
    obscureText: obscure,
    decoration: InputDecoration(labelText: label, isDense: true),
    validator: (value) {
      final text = value ?? '';
      if (text.isEmpty) return '请输入$label';
      if (validateLength && (text.length < 8 || text.length > 128)) {
        return '密码长度须为 8 到 128 位';
      }
      if (confirm != null && text != confirm!.text) return '两次输入的新密码不一致';
      return null;
    },
  );
}

String _shortId(String? value) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return '-';
  return text.length > 16
      ? '${text.substring(0, 8)}…${text.substring(text.length - 6)}'
      : text;
}
