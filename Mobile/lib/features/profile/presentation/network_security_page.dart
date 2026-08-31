import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_tunnel/secure_tunnel.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/security/managed_security_repository.dart';
import '../../../shared/widgets/mobile_primitives.dart';
import '../../network/application/tunnel_controller.dart';

class NetworkSecurityPage extends ConsumerWidget {
  const NetworkSecurityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(tunnelControllerProvider);
    final policy = ref.watch(managedPolicyStatusProvider);
    return Scaffold(
      appBar: AppBar(centerTitle: true, title: const Text('网络与安全')),
      body: value.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _Failure(
          message: error.toString(),
          onRetry: () => ref.invalidate(tunnelControllerProvider),
        ),
        data: (data) {
          final connected = data.status.isConnected;
          final runtimeCoreVersion = data.runtime?.coreVersion ?? '';
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 28),
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  height: 36,
                  child: TextButton.icon(
                    onPressed: data.synchronizing
                        ? null
                        : () => _synchronize(context, ref),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.sync_rounded, size: 18),
                    label: const Text('重新检测', style: TextStyle(fontSize: 13)),
                  ),
                ),
              ),
              MobileSurface(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color:
                                (connected
                                        ? AppColors.primary
                                        : AppColors.warning)
                                    .withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Icon(
                            Icons.wifi_rounded,
                            size: 22,
                            color: connected
                                ? AppColors.primary
                                : AppColors.warning,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                '连接状态',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                connected
                                    ? '安全连接正常'
                                    : _phaseLabel(data.status.phase),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: connected
                                      ? AppColors.success
                                      : AppColors.warning,
                                ),
                              ),
                              if (!connected &&
                                  data.message != null &&
                                  data.message!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  data.message!,
                                  maxLines: 2,
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
                      ],
                    ),
                    const Divider(height: 18),
                    _InfoRow(
                      '策略标识',
                      data.status.profileId.isEmpty
                          ? '未安装'
                          : data.status.profileId,
                    ),
                    _InfoRow(
                      '策略版本',
                      data.status.profileVersion.isEmpty
                          ? '-'
                          : data.status.profileVersion,
                    ),
                    _InfoRow(
                      '核心版本',
                      data.status.coreVersion.isEmpty
                          ? (runtimeCoreVersion.isEmpty
                                ? '-'
                                : runtimeCoreVersion)
                          : data.status.coreVersion,
                    ),
                    _InfoRow(
                      '运行平台',
                      [
                        data.runtime?.platform ?? '',
                        data.runtime?.architecture ?? '',
                      ].where((v) => v.isNotEmpty).join(' · '),
                    ),
                    _InfoRow(
                      '上传 / 下载',
                      '${_bytes(data.status.uploadBytes)} / ${_bytes(data.status.downloadBytes)}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              MobileSurface(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: policy.when(
                  loading: () => const _InfoRow('管理策略', '正在校验'),
                  error: (error, _) => Column(
                    children: [
                      const _InfoRow('管理策略', '校验失败'),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _policyError(error),
                              style: const TextStyle(
                                color: AppColors.secondaryText,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                          SizedBox(
                            height: 34,
                            child: TextButton(
                              onPressed: () =>
                                  ref.invalidate(managedPolicyStatusProvider),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              child: const Text(
                                '重试',
                                style: TextStyle(fontSize: 13),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  data: (status) => Column(
                    children: [
                      _InfoRow(
                        '管理策略',
                        status.enabled ? '已启用 · 签名有效' : '未启用 · 签名有效',
                      ),
                      _InfoRow(
                        '管理版本',
                        status.policyVersion.isEmpty
                            ? '-'
                            : status.policyVersion,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static Future<void> _synchronize(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(tunnelControllerProvider.notifier).synchronize();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  static String _phaseLabel(TunnelPhase phase) => switch (phase) {
    TunnelPhase.connected => '安全连接正常',
    TunnelPhase.preparing => '正在准备安全连接',
    TunnelPhase.connecting => '正在建立安全连接',
    TunnelPhase.reconnecting => '正在恢复安全连接',
    TunnelPhase.stopping => '正在断开安全连接',
    TunnelPhase.failed => '安全连接不可用',
    TunnelPhase.disconnected => '安全连接未启用',
    TunnelPhase.unavailable => '当前设备不支持安全连接',
  };
}

String _policyError(Object error) {
  if (error is DioException && error.response?.statusCode == 401) {
    return '登录已失效，请重新登录';
  }
  if (error is TimeoutException) return '检查超时，请稍后重试';
  if (error is FormatException) return error.message;
  return '策略服务暂不可用';
}

String _bytes(int value) {
  if (value < 1024) return '$value B';
  if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
  return '${(value / 1024 / 1024).toStringAsFixed(1)} MB';
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        SizedBox(
          width: 104,
          child: Text(
            label,
            style: const TextStyle(color: AppColors.secondaryText),
          ),
        ),
        Expanded(child: Text(value)),
      ],
    ),
  );
}

class _Failure extends StatelessWidget {
  const _Failure({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded, color: AppColors.error),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 14),
          OutlinedButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    ),
  );
}
