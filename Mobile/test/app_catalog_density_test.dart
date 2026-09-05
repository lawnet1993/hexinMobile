import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/core/theme/tdesign_icons.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/workbench/domain/app_catalog.dart';
import 'package:hexing_terminal_mobile/features/workbench/presentation/all_apps_page.dart';
import 'package:hexing_terminal_mobile/features/workbench/presentation/workbench_page.dart';

OaApplicationCatalogItem _item(
  String key,
  String name,
  String category,
  String icon,
) => OaApplicationCatalogItem(
  applicationKey: key,
  name: name,
  category: category,
  iconKey: icon,
  iconDataUrl: null,
  displayOrder: 0,
  configurationKind: 'approval',
  configurationId: 'config-$key',
  approvalTemplateId: 'template-$key',
  allowOfflineDraft: true,
  availabilitySource: 'department',
  sourceDepartmentId: 'fixture',
);

final _catalog = OaApplicationCatalog(
  catalogVersion: 'current-desktop-key-fixture',
  items: [
    _item('attendance.punch', '打卡', '考勤', 'access_time'),
    _item('attendance.leave', '请假审批', '考勤', 'event_busy'),
    _item('attendance.overtime', '加班审批', '考勤', 'more_time'),
    _item('attendance.business_trip', '出差审批', '考勤', 'flight_takeoff'),
    _item('expense.reimbursement', '报销审批', '费用', 'receipt_long'),
    _item('attendance.punch_correction', '补卡审批', '考勤', 'event_repeat'),
    _item('finance.payment_request', '请款审批', '财务', 'payments'),
    _item('finance.advance_request', '借支审批', '财务', 'account_balance_wallet'),
    _item('procurement.purchase_request', '采购申请', '采购', 'shopping_cart'),
    _item('administration.seal_use', '用印申请', '行政', 'approval'),
  ],
);

void main() {
  test('current desktop catalog icon keys have distinct meaningful glyphs', () {
    final expected = <String, IconData>{
      'access_time': TDIcons.calendarEdit,
      'event_busy': TDIcons.userTime,
      'more_time': TDIcons.time,
      'flight_takeoff': TDIcons.work,
      'receipt_long': TDIcons.file1,
      'event_repeat': TDIcons.calendarEvent,
      'payments': TDIcons.money,
      'account_balance_wallet': const IconData(0xE818, fontFamily: 'TDIcons'),
      'shopping_cart': TDIcons.cart,
    };
    for (final entry in expected.entries) {
      expect(
        MobileAppCatalog.iconForKey(entry.key),
        entry.value,
        reason: entry.key,
      );
    }
    final apps = MobileAppCatalog.fromCatalog(_catalog.items);
    expect(apps.last.icon, TDIcons.fileSafety);
    expect(apps.map((app) => app.route).whereType<String>(), hasLength(10));
    expect(MobileAppCatalog.iconForKey('not-a-known-icon'), Icons.apps_rounded);
  });

  for (final width in [360.0, 411.0]) {
    testWidgets('category rows do not repeat safe-area padding at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 24, bottom: 34);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            oaApplicationCatalogProvider.overrideWith((ref) async => _catalog),
          ],
          child: const MaterialApp(home: AllAppsPage()),
        ),
      );
      await tester.pumpAndSettle();
      for (final grid in tester.widgetList<GridView>(find.byType(GridView))) {
        expect(grid.padding, EdgeInsets.zero);
        expect(grid.primary, false);
      }
      final categories = ['考勤', '费用', '财务', '采购', '行政'];
      for (var i = 1; i < categories.length; i++) {
        final current = tester
            .getTopLeft(find.byKey(Key('all-app-category-${categories[i]}')))
            .dy;
        final previous = tester
            .getTopLeft(
              find.byKey(Key('all-app-category-${categories[i - 1]}')),
            )
            .dy;
        expect(current - previous, lessThanOrEqualTo(102));
      }
      expect(
        tester.getSize(find.byKey(const Key('all-app-catalog-surface'))).height,
        lessThanOrEqualTo(515),
      );
      for (final item in _catalog.items) {
        expect(
          tester.getSize(
            find.byKey(Key('all-app-icon-${item.applicationKey}')),
          ),
          const Size(32, 32),
        );
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'long label with large text remains tappable and uses the original route',
    (tester) async {
      tester.view.physicalSize = const Size(360, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final item = _item(
        'finance.payment_request',
        '外站通道及数据费用请款',
        '财务',
        'payments',
      );
      final router = GoRouter(
        initialLocation: '/apps',
        routes: [
          GoRoute(path: '/apps', builder: (_, _) => const AllAppsPage()),
          GoRoute(
            path: '/apply/:applicationKey',
            builder: (_, state) => Scaffold(
              body: Text(
                '${state.pathParameters['applicationKey']} / ${state.uri.queryParameters['templateId']}',
              ),
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            oaApplicationCatalogProvider.overrideWith(
              (ref) async => OaApplicationCatalog(
                catalogVersion: 'large-text',
                items: [item],
              ),
            ),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.5)),
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final label = tester.widget<Text>(find.text(item.name));
      expect(label.maxLines, 3);
      final tile = find.ancestor(
        of: find.text(item.name),
        matching: find.byType(InkResponse),
      );
      expect(tester.getSize(tile).height, greaterThanOrEqualTo(88));
      expect(tester.getSize(tile).width, greaterThanOrEqualTo(48));
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(
        find.text('finance.payment_request / template-finance.payment_request'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'home and all apps share configured icon rendering independent of title',
    (tester) async {
      final item = _item('custom.application', '改名后的应用', '测试', 'emoji:👩‍💻');
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (_, _) => const WorkbenchPage()),
          GoRoute(path: '/apps', builder: (_, _) => const AllAppsPage()),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            oaBootstrapProvider.overrideWith(
              (ref) async => PreviewData.oaBootstrap,
            ),
            oaApplicationCatalogProvider.overrideWith(
              (ref) async =>
                  OaApplicationCatalog(catalogVersion: 'custom', items: [item]),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('👩‍💻'), findsOneWidget);
      await tester.tap(find.text('全部应用'));
      await tester.pumpAndSettle();
      expect(find.text('👩‍💻'), findsOneWidget);
      expect(find.text(item.name), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
