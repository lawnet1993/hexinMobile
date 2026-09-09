import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

final appVersionProvider = FutureProvider<String>((ref) async {
  final packageInfo = await PackageInfo.fromPlatform();
  return packageInfo.version.trim();
});

/// Displays the version embedded in the installed package instead of a
/// duplicated UI constant that can drift from login and update protocols.
class AppVersionLabel extends ConsumerWidget {
  const AppVersionLabel({
    super.key,
    this.style,
    this.textAlign,
    this.prefix = 'v',
    this.unavailableText = '',
  });

  final TextStyle? style;
  final TextAlign? textAlign;
  final String prefix;
  final String unavailableText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider).when(
      data: (value) => value,
      error: (_, _) => '',
      loading: () => '',
    );
    final value = version.isEmpty ? unavailableText : '$prefix$version';
    if (value.isEmpty) return const SizedBox.shrink();
    return Text(value, textAlign: textAlign, style: style);
  }
}
