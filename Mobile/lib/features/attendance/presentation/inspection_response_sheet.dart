import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/mobile_bottom_sheets.dart';
import '../../collaboration/data/collaboration_repositories.dart';
import '../../collaboration/domain/collaboration_models.dart';

bool _inspectionPromptInFlight = false;

Future<String?> showInspectionResponseSheet(
  BuildContext context,
  OaActiveInspection inspection,
) => showMobileChoiceSheet<String>(
  context,
  title: inspection.title.trim().isEmpty ? '在岗确认' : inspection.title.trim(),
  options: [
    MobileSheetOption(
      value: 'present',
      label: '确认在岗',
      subtitle: inspection.message.trim(),
      icon: Icons.how_to_reg_outlined,
    ),
    const MobileSheetOption(
      value: 'unavailable',
      label: '暂时无法响应',
      icon: Icons.schedule_outlined,
    ),
  ],
);

Future<bool> showActiveInspectionPrompt({
  required BuildContext context,
  required WidgetRef ref,
  Set<String>? promptedIds,
  bool showEmpty = false,
}) async {
  if (_inspectionPromptInFlight) return false;
  _inspectionPromptInFlight = true;
  try {
    final repository = ref.read(oaRepositoryProvider);
    final items = await repository.activeInspections();
    if (!context.mounted) return false;
    final pending = items
        .where(
          (item) =>
              item.responseStatus.toLowerCase() == 'pending' &&
              !(promptedIds?.contains(item.inspectionId) ?? false),
        )
        .firstOrNull;
    if (pending == null) {
      if (showEmpty) {
        await showMobileMessageSheet(
          context,
          title: '在岗确认',
          message: '当前没有待确认的在岗巡检',
        );
      }
      return false;
    }

    promptedIds?.add(pending.inspectionId);
    await repository.markInspectionOpened(pending.inspectionId);
    if (!context.mounted) return false;
    final status = await showInspectionResponseSheet(context, pending);
    if (status == null) {
      promptedIds?.remove(pending.inspectionId);
      return true;
    }
    await repository.respondInspection(pending.inspectionId, status);
    ref.invalidate(oaActiveInspectionsProvider);
    return true;
  } catch (_) {
    if (showEmpty && context.mounted) {
      await showMobileMessageSheet(
        context,
        title: '在岗确认',
        message: '当前无法读取在岗巡检，请稍后重试',
      );
    }
    return false;
  } finally {
    _inspectionPromptInFlight = false;
  }
}
