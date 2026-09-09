import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/mobile_primitives.dart';

/// Mobile only surfaces the desktop security boundary and related reminders.
/// Site tunnel diagnostics and controls belong to the Windows terminal.
class NetworkSecurityPage extends StatelessWidget {
  const NetworkSecurityPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(centerTitle: true, title: const Text('网络与安全')),
    body: ListView(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      children: const [
        MobileSurface(
          key: Key('desktop-security-reminder'),
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ReminderIcon(),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '安全连接由桌面端管理',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 5),
                    Text(
                      '移动端的消息与审批直接同步，不启用站点隧道。策略变化、设备异常和站点提醒会进入通知中心。',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: AppColors.secondaryText,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ReminderIcon extends StatelessWidget {
  const _ReminderIcon();

  @override
  Widget build(BuildContext context) => Container(
    width: 34,
    height: 34,
    decoration: BoxDecoration(
      color: const Color(0xFFEAF2FF),
      borderRadius: BorderRadius.circular(8),
    ),
    alignment: Alignment.center,
    child: const Icon(
      Icons.desktop_windows_outlined,
      size: 19,
      color: AppColors.primary,
    ),
  );
}
