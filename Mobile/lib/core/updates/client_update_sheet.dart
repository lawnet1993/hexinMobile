import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import 'client_update_repository.dart';

typedef ClientUpdateDownloadAction = Future<void> Function();

Future<void> showClientUpdateSheet(
  BuildContext context, {
  required ClientUpdateInfo info,
  required ClientUpdateDownloadAction onDownload,
}) {
  if (info.isMandatory) {
    return showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierColor: const Color(0x5C000000),
      builder: (_) => PopScope(
        canPop: false,
        child: Dialog(
          key: const Key('client-update-dialog'),
          alignment: Alignment.center,
          backgroundColor: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF1C222B)
              : Colors.white,
          surfaceTintColor: Colors.transparent,
          shadowColor: Colors.transparent,
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 24,
          ),
          constraints: const BoxConstraints(maxWidth: 360),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: SingleChildScrollView(
            child: _ClientUpdateSheet(info: info, onDownload: onDownload),
          ),
        ),
      ),
    );
  }
  return showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    isDismissible: !info.isMandatory,
    enableDrag: !info.isMandatory,
    showDragHandle: !info.isMandatory,
    builder: (sheetContext) => PopScope(
      canPop: !info.isMandatory,
      child: _ClientUpdateSheet(info: info, onDownload: onDownload),
    ),
  );
}

class _ClientUpdateSheet extends StatefulWidget {
  const _ClientUpdateSheet({required this.info, required this.onDownload});

  final ClientUpdateInfo info;
  final ClientUpdateDownloadAction onDownload;

  @override
  State<_ClientUpdateSheet> createState() => _ClientUpdateSheetState();
}

class _ClientUpdateSheetState extends State<_ClientUpdateSheet> {
  bool _opening = false;

  Future<void> _download() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      await widget.onDownload();
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final info = widget.info;
    return SafeArea(
      top: false,
      child: Padding(
        key: const Key('client-update-sheet'),
        padding: EdgeInsets.fromLTRB(18, info.isMandatory ? 20 : 0, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    info.isMandatory ? '必须更新客户端' : '发现新版本',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!info.isMandatory)
                  SizedBox.square(
                    dimension: 36,
                    child: IconButton(
                      key: const Key('client-update-close'),
                      tooltip: '关闭',
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 21),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _UpdateMeta(label: '版本', value: 'v${info.latestVersion}'),
                if (info.packageSize > 0) ...[
                  _UpdateMeta(
                    label: '大小',
                    value: _formatPackageSize(info.packageSize),
                  ),
                ],
                if (info.isMandatory) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE9E8),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      '强制更新',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (info.releaseNotes.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                key: const Key('client-update-release-notes'),
                constraints: const BoxConstraints(maxHeight: 132),
                child: SingleChildScrollView(
                  child: Text(
                    info.releaseNotes.trim(),
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: AppColors.secondaryText,
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!info.isMandatory)
                  TextButton(
                    key: const Key('client-update-later'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(64, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('稍后'),
                  ),
                if (!info.isMandatory) const SizedBox(width: 8),
                FilledButton.icon(
                  key: const Key('client-update-download'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(112, 40),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: _opening ? null : _download,
                  icon: _opening
                      ? const SizedBox.square(
                          dimension: 15,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.download_rounded, size: 18),
                  label: Text(_opening ? '正在打开' : '下载更新'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UpdateMeta extends StatelessWidget {
  const _UpdateMeta({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFEAF2FF),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      '$label $value',
      style: const TextStyle(
        fontSize: 12,
        color: AppColors.primary,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

String _formatPackageSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
}
