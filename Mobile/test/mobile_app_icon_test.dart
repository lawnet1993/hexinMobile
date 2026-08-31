import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/workbench/domain/app_catalog.dart';

void main() {
  test('empty server catalog does not invent workbench applications', () {
    final entries = MobileAppCatalog.fromCatalog(const []);
    expect(entries, isEmpty);
    expect(
      MobileAppCatalog.entries.firstWhere((item) => item.title == '日程').route,
      '/schedule',
    );
    expect(
      MobileAppCatalog.entries.firstWhere((item) => item.title == '公司公告').route,
      '/notifications?tab=announcements',
    );
  });

  const standardIcons = <String, IconData>{
    'approval': Icons.description_outlined,
    'attendance': Icons.access_time_rounded,
    'expense': Icons.attach_money_rounded,
    'travel': Icons.directions_car_rounded,
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

  test('all admin template icon keys map to the expected mobile icons', () {
    for (final entry in standardIcons.entries) {
      expect(
        MobileAppCatalog.iconForKey(entry.key),
        entry.value,
        reason: 'Missing or mismatched mobile icon: ${entry.key}',
      );
    }
    expect(MobileAppCatalog.iconForKey('unknown-icon'), Icons.apps_rounded);
  });

  test('catalog keeps the server icon key and custom image data', () {
    const dataUrl =
        'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwC'
        'AAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=';
    final entries = MobileAppCatalog.fromCatalog([
      _catalogItem(iconKey: 'emoji:👩‍💻'),
      _catalogItem(iconKey: 'custom', iconDataUrl: dataUrl),
    ]);

    expect(entries[0].iconKey, 'emoji:👩‍💻');
    expect(entries[0].iconDataUrl, isNull);
    expect(entries[1].iconKey, 'custom');
    expect(entries[1].iconDataUrl, dataUrl);
    expect(entries[0].route, '/apply/test.application?templateId=template-id');
    expect(entries, hasLength(2), reason: '不得混入非工作台快捷入口');
  });

  testWidgets('custom emoji renders the first complete grapheme', (
    tester,
  ) async {
    await _pumpIcon(tester, iconKey: 'emoji:👩‍💻');

    expect(find.text('👩‍💻'), findsOneWidget);
    expect(find.text('👩'), findsNothing);
  });

  testWidgets('invalid base64 custom image falls back to the selected icon', (
    tester,
  ) async {
    await _pumpIcon(
      tester,
      iconKey: 'security',
      iconDataUrl: 'data:image/png;base64,not-valid-base64!',
    );

    expect(find.byIcon(Icons.security_rounded), findsOneWidget);
  });

  testWidgets('undecodable custom image bytes fall back without an exception', (
    tester,
  ) async {
    await _pumpIcon(
      tester,
      iconKey: 'security',
      iconDataUrl: 'data:image/png;base64,bm90LWFuLWltYWdl',
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.security_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

OaApplicationCatalogItem _catalogItem({
  required String iconKey,
  String? iconDataUrl,
}) => OaApplicationCatalogItem(
  applicationKey: 'test.application',
  name: '测试应用',
  category: '测试',
  iconKey: iconKey,
  iconDataUrl: iconDataUrl,
  displayOrder: 1,
  configurationKind: 'approval',
  configurationId: 'configuration-id',
  approvalTemplateId: 'template-id',
  allowOfflineDraft: true,
  availabilitySource: 'department',
  sourceDepartmentId: 'department-id',
);

Future<void> _pumpIcon(
  WidgetTester tester, {
  required String iconKey,
  String? iconDataUrl,
}) => tester.pumpWidget(
  MaterialApp(
    home: Center(
      child: MobileAppIcon(
        iconKey: iconKey,
        iconDataUrl: iconDataUrl,
        fallback: Icons.error_outline,
      ),
    ),
  ),
);
