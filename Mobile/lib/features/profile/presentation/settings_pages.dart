import 'dart:async';

import 'package:dio/dio.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/device/mobile_device_identity.dart';
import '../../../core/network/api_client.dart';
import '../../../core/notifications/mobile_push_registration.dart';
import '../../../core/storage/secure_session_store.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/theme_mode_controller.dart';
import '../../../core/updates/client_update_repository.dart';
import '../../../core/updates/client_update_sheet.dart';
import '../../../shared/errors/mobile_error_text.dart';
import '../../../shared/widgets/mobile_bottom_sheets.dart';
import '../../auth/application/auth_controller.dart';
import '../../collaboration/application/mobile_device_authorization_coordinator.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/data/im_member_presence.dart';
import '../../collaboration/domain/collaboration_models.dart';
import '../../network/application/tunnel_controller.dart';

final accountSecurityDeviceIdentityProvider =
    FutureProvider<MobileDeviceIdentity>(
      (ref) => ref.watch(mobileDeviceIdentityProvider).resolve(),
    );

class AccountSecurityPage extends ConsumerStatefulWidget {
  const AccountSecurityPage({super.key});

  @override
  ConsumerState<AccountSecurityPage> createState() =>
      _AccountSecurityPageState();
}

class _AccountSecurityPageState extends ConsumerState<AccountSecurityPage> {
  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).value;
    final member = ref.watch(imBootstrapProvider).value?.currentMember;
    final realtimeAvailability = ref.watch(imRealtimeAvailabilityProvider);
    final identity = ref.watch(accountSecurityDeviceIdentityProvider);
    return _SettingsScaffold(
      title: '账户与安全',
      children: [
        _SettingsSection(
          title: '终端账户',
          children: [
            _ValueRow(label: '账号', value: session?.username ?? '-'),
            _ValueRow(
              label: '当前设备',
              value: identity.when(
                data: _accountSecurityDeviceLabel,
                loading: () => '当前移动设备',
                error: (_, _) => '当前移动设备',
              ),
            ),
            _ValueRow(
              label: '登录状态',
              value: _accountSecurityLoginStatus(
                hasSession: session != null,
                realtimeAvailability: realtimeAvailability,
                memberOnline: watchMemberPresence(ref, member, transportAvailable:
                    realtimeAvailability == ImRealtimeAvailability.available).online,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SettingsSection(
          children: [
            ListTile(
              key: const Key('open-change-password'),
              dense: true,
              minTileHeight: 48,
              title: const Text('修改登录密码', style: TextStyle(fontSize: 14)),
              trailing: const Icon(Icons.chevron_right_rounded, size: 20),
              onTap: _openChangePassword,
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openChangePassword() => showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: false,
    builder: (_) => const _ChangePasswordSheet(),
  );
}

String _accountSecurityLoginStatus({
  required bool hasSession,
  required ImRealtimeAvailability realtimeAvailability,
  required bool? memberOnline,
}) {
  if (!hasSession) return '已失效';
  return switch (realtimeAvailability) {
    ImRealtimeAvailability.connecting => '已登录·同步中',
    ImRealtimeAvailability.unavailable => '已登录·同步中断',
    ImRealtimeAvailability.available => switch (memberOnline) {
      true => '已登录·在线',
      false => '已登录·离线',
      null => '已登录',
    },
  };
}

String _accountSecurityDeviceLabel(MobileDeviceIdentity identity) {
  final rawName = identity.name.trim();
  final normalized = rawName.toLowerCase();
  final name =
      normalized.contains('sdk_gphone') || normalized.contains('emulator')
      ? 'Android 模拟器'
      : rawName.isEmpty
      ? '当前移动设备'
      : rawName;
  final operatingSystem = identity.operatingSystem.trim();
  return operatingSystem.isEmpty ? name : '$name · $operatingSystem';
}

class _ChangePasswordSheet extends ConsumerStatefulWidget {
  const _ChangePasswordSheet();

  @override
  ConsumerState<_ChangePasswordSheet> createState() =>
      _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends ConsumerState<_ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  final _nextFocus = FocusNode();
  final _confirmFocus = FocusNode();
  bool _submitting = false;
  bool _currentObscure = true;
  bool _nextObscure = true;
  bool _confirmObscure = true;
  bool _validationAttempted = false;
  String? _submitError;

  bool get _canSubmit =>
      _current.text.isNotEmpty &&
      _next.text.isNotEmpty &&
      _confirm.text.isNotEmpty &&
      !_submitting;

  @override
  void initState() {
    super.initState();
    _current.addListener(_handleFieldChange);
    _next.addListener(_handleFieldChange);
    _confirm.addListener(_handleFieldChange);
  }

  void _handleFieldChange() {
    if (!mounted) return;
    setState(() => _submitError = null);
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    _nextFocus.dispose();
    _confirmFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_submitting,
    child: SafeArea(
    top: false,
    child: AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Form(
          key: _formKey,
          child: Column(
            key: const Key('change-password-form-content'),
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '修改登录密码',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: _submitting
                        ? null
                        : () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, size: 19),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              _PasswordField(
                fieldKey: const Key('current-password-field'),
                onSubmitted: (_) => _nextFocus.requestFocus(),
                enabled: !_submitting,
                validateOnChange: _validationAttempted,
                textInputAction: TextInputAction.next,
                controller: _current,
                label: '当前密码',
                obscure: _currentObscure,
                onToggleObscure: () =>
                    setState(() => _currentObscure = !_currentObscure),
              ),
              const SizedBox(height: 8),
              _PasswordField(
                fieldKey: const Key('new-password-field'),
                focusNode: _nextFocus,
                onSubmitted: (_) => _confirmFocus.requestFocus(),
                enabled: !_submitting,
                validateOnChange: _validationAttempted,
                textInputAction: TextInputAction.next,
                controller: _next,
                label: '新密码',
                obscure: _nextObscure,
                onToggleObscure: () =>
                    setState(() => _nextObscure = !_nextObscure),
                validateLength: true,
              ),
              const SizedBox(height: 8),
              _PasswordField(
                fieldKey: const Key('confirm-password-field'),
                focusNode: _confirmFocus,
                enabled: !_submitting,
                validateOnChange: _validationAttempted,
                controller: _confirm,
                label: '再次输入新密码',
                obscure: _confirmObscure,
                onToggleObscure: () =>
                    setState(() => _confirmObscure = !_confirmObscure),
                confirm: _next,
              ),
              const SizedBox(height: 8),
              const Text(
                '修改成功后，其他设备需重新登录',
                style: TextStyle(
                  fontSize: 11.5,
                  color: AppColors.secondaryText,
                ),
              ),
              if (_submitError != null) ...[
                const SizedBox(height: 6),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _submitError!,
                    key: const Key('change-password-error'),
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  key: const Key('change-password-submit'),
                  width: 118,
                  height: 36,
                  child: FilledButton(
                    onPressed: _canSubmit ? _changePassword : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(
                      _submitting ? '提交中…' : '确认修改',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    ),
  );

  Future<void> _changePassword() async {
    if (_submitting) return;
    setState(() => _validationAttempted = true);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final session = ref.read(authControllerProvider).value;
    if (session == null) return;
    final oldPassword = _current.text;
    final newPassword = _next.text;
    final sessionStore = ref.read(secureSessionStoreProvider);
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      await ref
          .read(dioProvider)
          .post<void>(
            '/api/client/change-password',
            options: Options(
              followRedirects: false,
              headers: {
                'Authorization': 'Bearer ${session.accessToken}',
                'X-Device-Id': session.deviceId,
              },
            ),
            data: {
              'deviceId': session.deviceId,
              'currentPassword': oldPassword,
              'newPassword': newPassword,
            },
          )
          .timeout(const Duration(seconds: 12));
      // A successful server change remains successful even if local cleanup
      // fails. Never encourage retrying a password already accepted remotely.
      var credentialCleanupFailed = false;
      try {
        await sessionStore.clearCredentialIfMatches(session.username, oldPassword);
      } catch (_) {
        credentialCleanupFailed = true;
      }
      if (!mounted || !_isCurrentSession(session)) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(credentialCleanupFailed
              ? '密码已修改，本机登录信息清理失败，请关闭记住密码'
              : '密码已修改，其他设备需重新登录')));
      Navigator.pop(context);
    } catch (error) {
      if (!mounted || !_isCurrentSession(session)) return;
      setState(() {
        _submitError = _passwordChangeError(error);
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  bool _isCurrentSession(MobileSession expected) =>
      ref.read(authControllerProvider).value?.isSameSession(expected) == true;
}

String _passwordChangeError(Object error) {
  // Losing the response is not proof that the write never reached the server.
  if (error is TimeoutException ||
      (error is DioException &&
          (error.response?.statusCode == 408 ||
              (error.response?.statusCode ?? 0) >= 500 ||
              (error.response == null && error.type != DioExceptionType.connectionTimeout &&
                  error.type != DioExceptionType.badCertificate)))) {
    return '修改结果尚未确认，请稍后核实，勿重复提交';
  }
  if (error is DioException && error.response != null) {
    return mobileActionErrorText('修改未完成', error,
        fallback: '请检查当前密码和新密码后重试');
  }
  return '修改未完成，请检查连接后重试';
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileActionErrorText('设置失败', error))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pushDevice = ref.watch(imPushDeviceProvider);
    final runtimeToken = ref.watch(mobilePushRuntimeTokenProvider);
    final syncState = ref.watch(imRealtimeAvailabilityProvider);
    final syncConnecting = syncState == ImRealtimeAvailability.connecting;
    final syncUnavailable = syncState == ImRealtimeAvailability.unavailable;
    return _SettingsScaffold(
      title: '通知设置',
      children: [
        _SettingsSection(
          title: '应用内通知',
          children: [
            const KeyedSubtree(
              key: Key('in-app-notification-sources'),
              child: _ValueRow(label: '通知中心', value: '消息、审批与公告'),
            ),
            KeyedSubtree(
              key: const Key('in-app-notification-sync'),
              child: _ValueRow(
                label: '同步状态',
                value: syncConnecting
                    ? '正在连接'
                    : syncUnavailable
                    ? '连接恢复后同步'
                    : '实时同步',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SettingsSection(
          title: '系统推送',
          child: pushDevice.when(
            loading: () => const _PushLoadingTile(),
            error: (error, _) => _PushErrorTile(
              errorText: mobileActionErrorText('推送状态加载失败', error),
              onRetry: () => ref.invalidate(imPushDeviceProvider),
            ),
            data: (device) => runtimeToken.when(
              loading: () => const _PushLoadingTile(),
              error: (_, _) => const _PushChannelPendingTile(),
              data: (token) => device == null || token == null
                  ? const _PushChannelPendingTile()
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
                              : (value) =>
                                    _updatePrivacy(_privacyMode(value)),
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

class _PushLoadingTile extends StatelessWidget {
  const _PushLoadingTile();

  @override
  Widget build(BuildContext context) => const ListTile(
    key: Key('push-settings-loading'),
    dense: true,
    minTileHeight: 52,
    contentPadding: EdgeInsets.symmetric(horizontal: 14),
    leading: SizedBox.square(
      dimension: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
    title: Text('正在同步推送设置', style: TextStyle(fontSize: 13.5)),
  );
}

class _PushErrorTile extends StatelessWidget {
  const _PushErrorTile({required this.errorText, required this.onRetry});

  final String errorText;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: errorText,
    child: ExcludeSemantics(
      child: ListTile(
        key: const Key('push-settings-error'),
        dense: true,
        minTileHeight: 52,
        contentPadding: const EdgeInsets.fromLTRB(14, 0, 8, 0),
        leading: const Icon(
          Icons.error_outline_rounded,
          size: 19,
          color: AppColors.error,
        ),
        title: const Text(
          '推送状态加载失败',
          style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
        ),
        trailing: TextButton(onPressed: onRetry, child: const Text('重试')),
      ),
    ),
  );
}

class _PushChannelPendingTile extends StatelessWidget {
  const _PushChannelPendingTile();

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '服务端推送能力已接入，厂商推送通道待接入',
    child: ExcludeSemantics(
      child: ListTile(
        key: const Key('push-channel-pending'),
        dense: true,
        minTileHeight: 60,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
        leading: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const SizedBox.square(
            dimension: 32,
            child: Icon(
              Icons.notifications_off_outlined,
              size: 19,
              color: AppColors.primary,
            ),
          ),
        ),
        title: const Row(
          children: [
            Expanded(child: Text('厂商推送通道', style: TextStyle(fontSize: 14))),
            Text(
              '待接入',
              style: TextStyle(fontSize: 13, color: AppColors.secondaryText),
            ),
          ],
        ),
        subtitle: const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '服务端注册接口',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppColors.secondaryText,
                  ),
                ),
              ),
              Text(
                '已接入',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppColors.success,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
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
  static const _deviceSyncTimeout = Duration(seconds: 12);

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
    if (silent &&
        ref.read(imRealtimeAvailabilityProvider) !=
            ImRealtimeAvailability.available) {
      return;
    }
    setState(() => _registering = true);
    try {
      await ref
          .read(mobileDeviceAuthorizationCoordinatorProvider)
          .synchronize()
          .timeout(_deviceSyncTimeout);
    } catch (error) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(mobileErrorText(error, fallback: '设备授权失败，请稍后重试')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  Future<void> _revoke(ImDeviceAuthorization device) async {
    final confirmed = await showMobileConfirmSheet(
      context,
      title: '撤销设备授权',
      message: '撤销“${device.deviceName}”后，该设备需要重新登录。',
      confirmLabel: '撤销',
      destructive: true,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileActionErrorText('撤销失败', error))),
        );
      }
    } finally {
      if (mounted) setState(() => _revokingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider).value;
    final devices = ref.watch(imDeviceAuthorizationsProvider);
    final currentDevice = ref.watch(currentMobileDeviceAuthorizationProvider);
    final syncState = ref.watch(imRealtimeAvailabilityProvider);
    final syncConnecting = syncState == ImRealtimeAvailability.connecting;
    final syncUnavailable = syncState == ImRealtimeAvailability.unavailable;
    final loadedItems = devices.value ?? const <ImDeviceAuthorization>[];
    final visibleItems = loadedItems.isNotEmpty
        ? loadedItems
        : currentDevice == null
        ? const <ImDeviceAuthorization>[]
        : <ImDeviceAuthorization>[currentDevice];
    return _SettingsScaffold(
      title: '登录设备',
      children: [
        _SettingsSection(
          title: visibleItems.isEmpty ? null : '已授权设备',
          child: visibleItems.isNotEmpty
              ? Column(
                  children: [
                    if (syncConnecting || syncUnavailable)
                      _DeviceSyncUnavailable(
                        cached: true,
                        connecting: syncConnecting,
                        loading: _registering,
                        onRetry: _retryDevices,
                      ),
                    for (var i = 0; i < visibleItems.length; i++) ...[
                      _DeviceAuthorizationTile(
                        device: visibleItems[i],
                        currentDeviceId: session?.deviceId ?? '',
                        revoking: _revokingId == visibleItems[i].deviceId,
                        onRevoke: () => _revoke(visibleItems[i]),
                      ),
                      if (i < visibleItems.length - 1)
                        const Divider(height: 1, indent: 58),
                    ],
                  ],
                )
              : devices.when(
                  loading: () => _DeviceSyncUnavailable(
                    connecting: !syncUnavailable,
                    loading: _registering,
                    onRetry: _retryDevices,
                  ),
                  error: (error, _) => _DeviceSyncUnavailable(
                    message: mobileErrorText(error, fallback: '设备状态同步失败'),
                    connecting: syncConnecting,
                    loading: _registering,
                    onRetry: _retryDevices,
                  ),
                  data: (_) => syncConnecting || syncUnavailable
                      ? _DeviceSyncUnavailable(
                          connecting: syncConnecting,
                          loading: _registering,
                          onRetry: _retryDevices,
                        )
                      : _AuthorizeCurrentDevice(
                          registering: _registering,
                          onRegister: _registerCurrent,
                        ),
                ),
        ),
      ],
    );
  }

  void _retryDevices() {
    ref.invalidate(imDeviceAuthorizationsProvider);
    _registerCurrent();
  }
}

class _DeviceSyncUnavailable extends StatelessWidget {
  const _DeviceSyncUnavailable({
    required this.loading,
    required this.onRetry,
    this.cached = false,
    this.connecting = false,
    this.message,
  });

  final bool cached;
  final bool connecting;
  final String? message;
  final bool loading;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final active = connecting || loading;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          if (active)
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 1.8),
            )
          else
            const Icon(
              Icons.cloud_off_outlined,
              size: 19,
              color: AppColors.secondaryText,
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message ??
                  (active
                      ? cached
                            ? '正在同步 · 显示缓存'
                            : '正在同步设备'
                      : cached
                      ? '离线 · 显示缓存'
                      : '暂时无法同步设备'),
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.secondaryText,
              ),
            ),
          ),
          if (!active) TextButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}

class _AuthorizeCurrentDevice extends StatelessWidget {
  const _AuthorizeCurrentDevice({
    required this.registering,
    required this.onRegister,
  });

  final bool registering;
  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) => Padding(
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
          onPressed: registering ? null : onRegister,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text(registering ? '授权中…' : '授权当前设备'),
        ),
      ),
    ),
  );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileActionErrorText('主题保存失败', error))),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mobileActionErrorText('语言更新失败', error))),
        );
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
            children: [Text('请确认系统通知权限已开启，并在“通知设置”中启用对应提醒。')],
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
        title: '反馈与诊断',
        children: [
          _ValueRow(label: '联系方式', value: '请联系企业管理员'),
          _DiagnosticsAction(),
        ],
      ),
    ],
  );
}

class _DiagnosticsAction extends ConsumerWidget {
  const _DiagnosticsAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    key: const Key('copy-diagnostics-entry'),
    dense: true,
    minTileHeight: 48,
    title: const Text('诊断信息', style: TextStyle(fontSize: 14)),
    trailing: const Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.copy_all_outlined, size: 17, color: AppColors.primary),
        SizedBox(width: 5),
        Text('复制', style: TextStyle(fontSize: 13, color: AppColors.primary)),
      ],
    ),
    onTap: () => _copy(context, ref),
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
        const Column(
          key: Key('about-brand-block'),
          children: [
            Icon(Icons.shield_rounded, size: 40, color: AppColors.primary),
            SizedBox(height: 4),
            Text(
              '合兴智联',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 2),
            Text(
              '安全访问 · 高效协同',
              style: TextStyle(fontSize: 12.5, color: AppColors.secondaryText),
            ),
            SizedBox(height: 12),
          ],
        ),
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
  await showClientUpdateSheet(
    context,
    info: info,
    onDownload: () async {
      final uri = Uri.tryParse(info.packageUrl);
      if (uri == null ||
          !{'http', 'https'}.contains(uri.scheme.toLowerCase())) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('更新地址无效，请联系管理员')));
        }
        return;
      }
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    },
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
    final selected = await showMobileChoiceSheet<String>(
      context,
      title: label,
      selectedValue: value,
      options: values
          .map((item) => MobileSheetOption(value: item, label: item))
          .toList(),
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
    required this.fieldKey,
    required this.controller,
    required this.label,
    required this.obscure,
    required this.onToggleObscure,
    this.validateLength = false,
    this.confirm,
    this.enabled = true,
    this.validateOnChange = false,
    this.textInputAction = TextInputAction.done,
    this.focusNode,
    this.onSubmitted,
  });
  final Key fieldKey;
  final TextEditingController controller;
  final String label;
  final bool obscure;
  final VoidCallback onToggleObscure;
  final bool validateLength;
  final TextEditingController? confirm;
  final bool enabled;
  final bool validateOnChange;
  final TextInputAction textInputAction;
  final FocusNode? focusNode;
  final ValueChanged<String>? onSubmitted;
  @override
  Widget build(BuildContext context) => TextFormField(
    key: fieldKey,
    controller: controller,
    focusNode: focusNode,
    onFieldSubmitted: onSubmitted,
    enabled: enabled,
    textInputAction: textInputAction,
    enableSuggestions: false,
    autocorrect: false,
    autovalidateMode: validateOnChange ? AutovalidateMode.always : AutovalidateMode.disabled,
    obscureText: obscure,
    style: const TextStyle(fontSize: 14),
    decoration: InputDecoration(
      hintText: label,
      isDense: true,
      filled: true,
      fillColor: Theme.of(context).colorScheme.surfaceContainerHighest
          .withValues(alpha: .55),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      border: const OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      enabledBorder: const OutlineInputBorder(
        borderSide: BorderSide.none,
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderSide: BorderSide(color: AppColors.primary, width: 1),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      suffixIconConstraints: const BoxConstraints.tightFor(
        width: 36,
        height: 36,
      ),
      suffixIcon: IconButton(
        tooltip: obscure ? '显示$label' : '隐藏$label',
        onPressed: enabled ? onToggleObscure : null,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        visualDensity: VisualDensity.compact,
        icon: Icon(
          obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          size: 18,
        ),
      ),
    ),
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
