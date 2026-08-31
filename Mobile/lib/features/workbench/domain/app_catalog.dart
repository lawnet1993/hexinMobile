import 'dart:convert';

import 'package:flutter/material.dart';

import '../../collaboration/domain/collaboration_models.dart';

final class MobileAppEntry {
  const MobileAppEntry(
    this.title,
    this.subtitle,
    this.icon,
    this.color, {
    this.category = '常用',
    this.route,
    this.applicationKey = '',
    this.iconKey = '',
    this.iconDataUrl,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final String category;
  final String? route;
  final String applicationKey;
  final String iconKey;
  final String? iconDataUrl;
}

const _iconMap = <String, IconData>{
  'approval': Icons.description_outlined,
  'attendance': Icons.access_time_rounded,
  'leave': Icons.event_busy_rounded,
  'overtime': Icons.more_time_rounded,
  'travel': Icons.directions_car_rounded,
  'expense': Icons.attach_money_rounded,
  'correction': Icons.event_repeat_rounded,
  'audit': Icons.fact_check_outlined,
  'security': Icons.security_rounded,
  'settings': Icons.settings_rounded,
  'calendar': Icons.calendar_month_rounded,
  'meeting': Icons.groups_rounded,
  'announcement': Icons.campaign_outlined,
  'document': Icons.menu_book_rounded,
  'purchase': Icons.shopping_cart_rounded,
  'recruitment': Icons.person_add_alt_rounded,
  'training': Icons.school_rounded,
  'seal': Icons.local_printshop_rounded,
  'computer': Icons.laptop_rounded,
  'access': Icons.lock_rounded,
  'database': Icons.storage_rounded,
  'project': Icons.account_tree_rounded,
  'target': Icons.track_changes_rounded,
  'customer_service': Icons.support_agent_rounded,
  'tool': Icons.build_rounded,
  'home': Icons.home_work_rounded,
  'flag': Icons.flag_rounded,
};

class MobileAppIcon extends StatelessWidget {
  const MobileAppIcon({
    super.key,
    required this.iconKey,
    required this.fallback,
    this.iconDataUrl,
    this.color,
    this.size,
  });

  final String iconKey;
  final IconData fallback;
  final String? iconDataUrl;
  final Color? color;
  final double? size;

  @override
  Widget build(BuildContext context) {
    Widget fallbackIcon() =>
        Icon(_iconMap[iconKey] ?? fallback, size: size, color: color);

    if (iconDataUrl?.startsWith('data:image/') == true) {
      try {
        return Image.memory(
          base64Decode(iconDataUrl!.split(',').last),
          width: size ?? 29,
          height: size ?? 29,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => fallbackIcon(),
        );
      } on FormatException {
        // Fall back to the built-in icon when a cached custom image is invalid.
      }
    }
    if (iconKey.startsWith('emoji:')) {
      final value = iconKey.substring('emoji:'.length).trim();
      final icon = value.characters.isEmpty ? '' : value.characters.first;
      return Text(icon, style: TextStyle(fontSize: size ?? 29, height: 1));
    }
    return fallbackIcon();
  }
}

abstract final class MobileAppCatalog {
  static IconData iconForKey(String iconKey) =>
      _iconMap[iconKey] ?? Icons.apps_rounded;

  static String? routeForKey(String applicationKey) => switch (applicationKey) {
    'attendance.punch' => '/punch',
    'attendance.punch_correction' => '/attendance',
    _ => null,
  };

  static String? routeForCatalogItem(OaApplicationCatalogItem item) {
    final fixedRoute = routeForKey(item.applicationKey);
    if (fixedRoute != null) return fixedRoute;
    final templateId = item.approvalTemplateId?.trim() ?? '';
    if (templateId.isEmpty || item.applicationKey.isEmpty) return null;
    return Uri(
      path: '/apply/${item.applicationKey}',
      queryParameters: {'templateId': templateId},
    ).toString();
  }

  static Color colorForIndex(int index) => const [
    Color(0xFF1194A8),
    Color(0xFF246DD0),
    Color(0xFF7356C8),
    Color(0xFFC8752A),
    Color(0xFF238B6E),
    Color(0xFFC84D59),
  ][index % 6];

  static String descriptionFor(String applicationKey, String category) =>
      switch (applicationKey) {
        'attendance.punch' => '记录本次考勤',
        'attendance.leave' => '年假、事假、病假',
        'attendance.overtime' => '提交加班时段',
        'attendance.business_trip' => '行程与差旅说明',
        'expense.reimbursement' => '费用与凭证登记',
        'attendance.punch_correction' => '补充异常考勤',
        _ => category.isEmpty ? '企业协同应用' : category,
      };

  static List<MobileAppEntry> fromCatalog(
    List<OaApplicationCatalogItem> items,
  ) {
    if (items.isEmpty) return const <MobileAppEntry>[];
    return [
      for (var index = 0; index < items.length; index++)
        _fromCatalogItem(items[index], index),
    ];
  }

  static MobileAppEntry _fromCatalogItem(
    OaApplicationCatalogItem item,
    int index,
  ) {
    final iconKey = item.iconKey.isEmpty ? item.applicationKey : item.iconKey;
    return MobileAppEntry(
      item.name,
      descriptionFor(item.applicationKey, item.category),
      _iconForApplication(item.applicationKey, iconKey),
      colorForIndex(index),
      category: item.category.isEmpty ? '常用' : item.category,
      route: routeForCatalogItem(item),
      applicationKey: item.applicationKey,
      iconKey: iconKey,
      iconDataUrl: item.iconDataUrl,
    );
  }

  /// Keep core mobile-office actions semantically distinct even when an
  /// administrator configures the same generic approval icon for each item.
  static IconData _iconForApplication(String applicationKey, String iconKey) =>
      switch (applicationKey) {
        'attendance.punch' => Icons.calendar_month_outlined,
        'attendance.leave' => Icons.person_outline_rounded,
        'attendance.overtime' => Icons.schedule_rounded,
        'attendance.business_trip' => Icons.work_outline_rounded,
        'expense.reimbursement' => Icons.receipt_long_outlined,
        'attendance.punch_correction' => Icons.event_repeat_rounded,
        _ => iconForKey(iconKey),
      };

  static const entries = <MobileAppEntry>[
    MobileAppEntry(
      '上班打卡',
      '记录本次考勤',
      Icons.access_time_rounded,
      Color(0xFF1194A8),
      category: '考勤',
      applicationKey: 'attendance.punch',
      iconKey: 'attendance',
    ),
    MobileAppEntry(
      '请假申请',
      '年假、事假、病假',
      Icons.event_busy_rounded,
      Color(0xFF246DD0),
      category: '考勤',
      applicationKey: 'attendance.leave',
      iconKey: 'leave',
    ),
    MobileAppEntry(
      '加班申请',
      '提交加班时段',
      Icons.more_time_rounded,
      Color(0xFF7356C8),
      category: '考勤',
      applicationKey: 'attendance.overtime',
      iconKey: 'overtime',
    ),
    MobileAppEntry(
      '出差申请',
      '行程与差旅说明',
      Icons.flight_takeoff_rounded,
      Color(0xFFC8752A),
      category: '考勤',
      applicationKey: 'attendance.business_trip',
      iconKey: 'travel',
    ),
    MobileAppEntry(
      '报销申请',
      '费用与凭证登记',
      Icons.receipt_long_rounded,
      Color(0xFF238B6E),
      category: '费用',
      applicationKey: 'expense.reimbursement',
      iconKey: 'expense',
    ),
    MobileAppEntry(
      '补卡申请',
      '补充异常考勤',
      Icons.event_repeat_rounded,
      Color(0xFFC84D59),
      category: '考勤',
      applicationKey: 'attendance.punch_correction',
      iconKey: 'correction',
    ),
    MobileAppEntry(
      '审批中心',
      '处理我的审批',
      Icons.fact_check_outlined,
      Color(0xFF1677FF),
      category: '审批',
      route: '/todos',
    ),
    MobileAppEntry(
      '日程',
      '查看工作安排',
      Icons.calendar_month_outlined,
      Color(0xFF1194A8),
      category: '协作',
      route: '/schedule',
    ),
    MobileAppEntry(
      '公司公告',
      '查看公司通知',
      Icons.campaign_outlined,
      Color(0xFFF06718),
      category: '协作',
      route: '/notifications?tab=announcements',
    ),
    MobileAppEntry(
      '工作群组',
      '进入协作群组',
      Icons.groups_outlined,
      Color(0xFF1677FF),
      category: '协作',
      route: '/messages',
    ),
    MobileAppEntry(
      '登录设备',
      '查看设备安全',
      Icons.verified_user_outlined,
      Color(0xFF1677FF),
      category: '安全',
      route: '/login-devices',
    ),
    MobileAppEntry(
      '网络诊断',
      '检测安全连接',
      Icons.wifi_tethering_rounded,
      Color(0xFF12A84A),
      category: '安全',
      route: '/network-security',
    ),
  ];
}
