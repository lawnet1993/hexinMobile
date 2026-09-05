import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/workbench/presentation/all_apps_page.dart';
import 'package:hexing_terminal_mobile/features/workbench/presentation/workbench_page.dart';

final _account = NotifierProvider<_Account, String>(_Account.new);

class _Account extends Notifier<String> {
  @override
  String build() => 'first';
  void switchAccount() => state = 'second';
}

class _Availability extends OaSyncAvailabilityController {
  @override
  OaSyncAvailability build() => OaSyncAvailability.available;
}

const _empty = OaApplicationCatalog(catalogVersion: 'empty', items: []);
DioException _error([int? status]) => DioException(
  requestOptions: RequestOptions(path: '/catalog'),
  type: status == null
      ? DioExceptionType.connectionError
      : DioExceptionType.badResponse,
  response: status == null
      ? null
      : Response(
          requestOptions: RequestOptions(path: '/catalog'),
          statusCode: status,
          data: {'debug': 'sensitive-server-detail'},
        ),
);

Future<ProviderContainer> _open(
  WidgetTester tester, {
  required Future<OaApplicationCatalog> Function(String) load,
  Future<OaApplicationCatalog> Function()? refresh,
  bool home = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        oaSyncAvailabilityControllerProvider.overrideWith(_Availability.new),
        collaborationAccountScopeProvider.overrideWith(
          (ref) => ref.watch(_account),
        ),
        oaApplicationCatalogProvider.overrideWith(
          (ref) => load(ref.watch(_account)),
        ),
        oaApplicationCatalogRefresherProvider.overrideWithValue(
          refresh ?? () async => PreviewData.oaCatalog,
        ),
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
      ],
      child: MaterialApp(
        home: home ? const WorkbenchPage() : const AllAppsPage(),
      ),
    ),
  );
  await tester.pump();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(home ? WorkbenchPage : AllAppsPage)),
  );
  await tester.pump();
  return container;
}

void main() {
  for (final home in [false, true]) {
    testWidgets('catalog loading is not an empty result, home=$home', (
      tester,
    ) async {
      final pending = Completer<OaApplicationCatalog>();
      await _open(tester, home: home, load: (_) => pending.future);
      expect(find.text('应用加载中'), findsOneWidget);
      expect(find.text('暂无匹配应用'), findsNothing);
      expect(find.text('更多'), findsNothing);
      pending.complete(_empty);
      await tester.pumpAndSettle();
      expect(find.text('暂无可用应用'), findsOneWidget);
      expect(find.text('暂无匹配应用'), findsNothing);
    });
    testWidgets('catalog error exposes a real retry, home=$home', (
      tester,
    ) async {
      var ready = false;
      var refreshes = 0;
      await _open(
        tester,
        home: home,
        load: (_) async {
          if (!ready) throw _error(503);
          return PreviewData.oaCatalog;
        },
        refresh: () async {
          refreshes++;
          ready = true;
          return PreviewData.oaCatalog;
        },
      );
      await tester.pumpAndSettle();
      expect(find.text('应用加载失败'), findsOneWidget);
      expect(find.textContaining('sensitive-server-detail'), findsNothing);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(refreshes, 1);
      expect(find.text('请假申请'), findsOneWidget);
      expect(find.text('应用加载失败'), findsNothing);
    });
  }

  testWidgets(
    'only a populated catalog with an unmatched query says no matches',
    (tester) async {
      await _open(tester, load: (_) async => PreviewData.oaCatalog);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'not-an-application');
      await tester.pumpAndSettle();
      expect(find.text('暂无匹配应用'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.text('请假申请'), findsOneWidget);
    },
  );

  testWidgets(
    'offline cached catalog remains searchable while retry is deduplicated',
    (tester) async {
      final pending = Completer<OaApplicationCatalog>();
      var refreshes = 0;
      final container = await _open(
        tester,
        load: (_) async => PreviewData.oaCatalog,
        refresh: () {
          refreshes++;
          return pending.future;
        },
      );
      await tester.pumpAndSettle();
      container
          .read(oaSyncAvailabilityControllerProvider.notifier)
          .markUnavailable();
      await tester.pump();
      expect(find.text('连接暂不可用，显示缓存应用'), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const Key('application-catalog-status')))
            .height,
        lessThanOrEqualTo(44),
      );
      await tester.enterText(find.byType(TextField), '请假');
      await tester.pump();
      await tester.tap(find.text('重试'));
      await tester.pump();
      expect(find.text('正在更新应用'), findsOneWidget);
      expect(
        tester
            .getSize(find.byKey(const Key('application-catalog-status')))
            .height,
        44,
      );
      expect(find.text('请假申请'), findsOneWidget);
      expect(find.text('报销申请'), findsNothing);
      expect(find.text('重试'), findsNothing);
      expect(refreshes, 1);
      pending.completeError(_error());
      await tester.pumpAndSettle();
      expect(find.text('连接暂不可用，显示缓存应用'), findsOneWidget);
      expect(find.text('请假申请'), findsOneWidget);
      expect(
        tester.widget<EditableText>(find.byType(EditableText)).controller.text,
        '请假',
      );
    },
  );

  for (final status in [503, 403]) {
    testWidgets(
      'network recovery retries transient catalog error $status only',
      (tester) async {
        var calls = 0;
        final container = await _open(
          tester,
          load: (_) async {
            calls++;
            if (calls == 1) throw _error(status);
            return PreviewData.oaCatalog;
          },
        );
        await tester.pumpAndSettle();
        final availability = container.read(
          oaSyncAvailabilityControllerProvider.notifier,
        );
        availability.markUnavailable();
        await tester.pump();
        availability.markAvailable();
        await tester.pumpAndSettle();
        expect(calls, status == 503 ? 2 : 1);
        expect(
          find.text('请假申请'),
          status == 503 ? findsOneWidget : findsNothing,
        );
      },
    );
  }

  testWidgets('account switch clears cached entries even if next load fails', (
    tester,
  ) async {
    final pending = Completer<OaApplicationCatalog>();
    final container = await _open(
      tester,
      load: (account) async {
        if (account == 'second') return pending.future;
        return PreviewData.oaCatalog;
      },
    );
    await tester.pumpAndSettle();
    expect(find.text('请假申请'), findsOneWidget);
    container.read(_account.notifier).switchAccount();
    await tester.pump();
    expect(find.text('请假申请'), findsNothing);
    expect(find.text('应用加载中'), findsOneWidget);
    pending.completeError(_error(403));
    await tester.pumpAndSettle();
    expect(find.text('请假申请'), findsNothing);
    expect(find.text('应用加载失败'), findsOneWidget);
  });

  testWidgets(
    'late retry after account switch does not invalidate the new catalog',
    (tester) async {
      final pending = Completer<OaApplicationCatalog>();
      var secondLoads = 0;
      final container = await _open(
        tester,
        load: (account) async {
          if (account == 'second') {
            secondLoads++;
            return _empty;
          }
          throw _error();
        },
        refresh: () => pending.future,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('重试'));
      await tester.pump();
      container.read(_account.notifier).switchAccount();
      await tester.pumpAndSettle();
      pending.complete(PreviewData.oaCatalog);
      await tester.pumpAndSettle();
      expect(secondLoads, 1);
      expect(find.text('暂无可用应用'), findsOneWidget);
      expect(find.text('请假申请'), findsNothing);
    },
  );

  testWidgets('recovery during an in-flight request retries once, not a loop', (
    tester,
  ) async {
    final pending = Completer<OaApplicationCatalog>();
    var refreshes = 0;
    final container = await _open(
      tester,
      load: (_) => pending.future,
      refresh: () async {
        refreshes++;
        throw _error(503);
      },
    );
    final availability = container.read(
      oaSyncAvailabilityControllerProvider.notifier,
    );
    availability.markUnavailable();
    await tester.pump();
    availability.markAvailable();
    await tester.pump();
    pending.completeError(_error(503));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    expect(find.text('应用加载失败'), findsOneWidget);
    availability.markAvailable();
    await tester.pumpAndSettle();
    expect(refreshes, 1);
  });

  testWidgets(
    'same-account cache stays visible during background refresh failure',
    (tester) async {
      var fail = false;
      final container = await _open(
        tester,
        load: (_) async {
          if (fail) throw _error(503);
          return PreviewData.oaCatalog;
        },
      );
      await tester.pumpAndSettle();
      fail = true;
      container.invalidate(oaApplicationCatalogProvider);
      await tester.pump();
      expect(find.text('请假申请'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('请假申请'), findsOneWidget);
      expect(find.text('应用更新失败，显示缓存应用'), findsOneWidget);
    },
  );

  testWidgets('late retry after page disposal is ignored', (tester) async {
    final pending = Completer<OaApplicationCatalog>();
    await _open(
      tester,
      load: (_) async => throw _error(),
      refresh: () => pending.future,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    pending.completeError(_error(503));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
