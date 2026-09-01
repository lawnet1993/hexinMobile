import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:secure_tunnel/secure_tunnel.dart';

import '../../core/theme/app_colors.dart';
import '../../features/network/application/tunnel_controller.dart';
import 'terminal_avatar_assets.dart';

/// A dialog or bottom-sheet future completes as soon as `Navigator.pop` runs,
/// while its exit animation can still rebuild text fields for a few frames.
/// Dispose route-owned controllers only after that transition has settled.
Future<void> disposeRouteTextController(
  TextEditingController controller,
) async {
  await Future<void>.delayed(const Duration(milliseconds: 320));
  controller.dispose();
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 44});

  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFFE8F4FF),
      borderRadius: BorderRadius.circular(8),
    ),
    alignment: Alignment.center,
    child: Icon(
      Icons.shield_outlined,
      size: size * .66,
      color: const Color(0xFF118DA5),
    ),
  );
}

class InitialAvatar extends StatelessWidget {
  const InitialAvatar({
    super.key,
    required this.name,
    this.radius = 24,
    this.online,
    this.avatarKey = '',
    this.avatarDataUrl = '',
    this.backgroundColor = const Color(0xFFE7F0FF),
  });

  final String name;
  final double radius;
  final bool? online;
  final String avatarKey;
  final String avatarDataUrl;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      CircleAvatar(
        radius: radius,
        backgroundColor: backgroundColor,
        foregroundColor: AppColors.primary,
        foregroundImage: _avatarImage(
          avatarDataUrl.isNotEmpty
              ? avatarDataUrl
              : terminalAvatarDataUrls[avatarKey] ?? '',
        ),
        child: Text(
          name.trim().isEmpty ? '?' : name.trim().substring(0, 1),
          style: TextStyle(fontSize: radius * .72, fontWeight: FontWeight.w600),
        ),
      ),
      if (online != null)
        Positioned(
          right: 0,
          bottom: 1,
          child: Container(
            width: radius * .45,
            height: radius * .45,
            decoration: BoxDecoration(
              color: online! ? AppColors.success : const Color(0xFFB8BDC7),
              shape: BoxShape.circle,
              border: const Border.fromBorderSide(
                BorderSide(color: Colors.white, width: 2),
              ),
            ),
          ),
        ),
    ],
  );
}

Uint8List? _avatarBytes(String value) {
  if (!value.startsWith('data:image/') || !value.contains(';base64,')) {
    return null;
  }
  try {
    return base64Decode(value.substring(value.indexOf(',') + 1));
  } catch (_) {
    return null;
  }
}

ImageProvider<Object>? _avatarImage(String value) {
  final bytes = _avatarBytes(value);
  return bytes == null ? null : MemoryImage(bytes);
}

class NetworkIndicator extends ConsumerWidget {
  const NetworkIndicator({super.key, this.size = 22});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(tunnelControllerProvider);
    final status = value.value?.status;
    final phase = status?.phase;
    final (icon, color, message) = switch (phase) {
      TunnelPhase.connected => (
        Icons.wifi_rounded,
        const Color(0xFF12B75A),
        '安全连接正常',
      ),
      TunnelPhase.preparing ||
      TunnelPhase.connecting ||
      TunnelPhase.reconnecting ||
      TunnelPhase.stopping => (
        Icons.sync_rounded,
        AppColors.primary,
        '安全连接处理中',
      ),
      TunnelPhase.failed || TunnelPhase.unavailable => (
        Icons.wifi_off_rounded,
        const Color(0xFFE87918),
        status?.message ?? '安全连接不可用',
      ),
      TunnelPhase.disconnected => (
        Icons.wifi_off_rounded,
        AppColors.secondaryText,
        '安全连接未启用',
      ),
      null => (Icons.sync_rounded, AppColors.secondaryText, '正在检查安全连接'),
    };
    return Tooltip(
      message: message,
      child: Icon(icon, size: size, color: color),
    );
  }
}

class MobileSearchField extends StatelessWidget {
  const MobileSearchField({
    super.key,
    required this.hintText,
    this.onChanged,
    this.autofocus = false,
    this.controller,
    this.onSubmitted,
  });

  final String hintText;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final TextEditingController? controller;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 34,
    child: TextField(
      autofocus: autofocus,
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        hintText: hintText,
        hintStyle: const TextStyle(fontSize: 13.5),
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 36,
          minHeight: 34,
        ),
        filled: true,
        fillColor: const Color(0xFFF1F3F6),
        contentPadding: const EdgeInsets.symmetric(vertical: 7),
        border: const OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: AppColors.primary),
          borderRadius: BorderRadius.all(Radius.circular(8)),
        ),
      ),
    ),
  );
}

class MobileSurface extends StatelessWidget {
  const MobileSurface({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(10),
    clipBehavior: Clip.antiAlias,
    child: padding == null ? child : Padding(padding: padding!, child: child),
  );
}

class EnterprisePageHeader extends StatelessWidget {
  const EnterprisePageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.secondaryText,
                  ),
                ),
              ],
            ],
          ),
        ),
        ...actions,
      ],
    ),
  );
}

class CompactSwitch extends StatelessWidget {
  const CompactSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 36,
    height: 24,
    child: FittedBox(
      fit: BoxFit.contain,
      child: Switch(value: value, onChanged: onChanged),
    ),
  );
}

class FlatSectionTitle extends StatelessWidget {
  const FlatSectionTitle({
    super.key,
    required this.title,
    this.action,
    this.onAction,
  });

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: Row(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        if (action != null)
          TextButton(
            onPressed: onAction,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(action!),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
      ],
    ),
  );
}
