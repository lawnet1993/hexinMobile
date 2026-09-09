import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/todos/presentation/approval_request_page.dart';

const _reason = 'AI-UAT-workflow-recovery';

DioException _failure(int? status, {bool cancelled = false}) {
  final options = RequestOptions(path: '/workflow-preview');
  return DioException(
    requestOptions: options,
    type: cancelled
        ? DioExceptionType.cancel
        : status == null
        ? DioExceptionType.connectionError
        : DioExceptionType.badResponse,
    response: status == null
        ? null
        : Response(requestOptions: options, statusCode: status),
  );
}

Future<ProviderContainer> _open(
  WidgetTester tester,
  OaWorkflowPreviewLoader loader,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        oaBootstrapProvider.overrideWith(
          (ref) async => PreviewData.oaBootstrap,
        ),
        oaApplicationCatalogProvider.overrideWith(
          (ref) async => PreviewData.oaCatalog,
        ),
        imBootstrapProvider.overrideWith(
          (ref) async => PreviewData.imBootstrap,
        ),
        imDepartmentsProvider.overrideWith((ref) async => const []),
        oaDraftLoaderProvider.overrideWithValue((_) async => null),
        oaWorkflowPreviewLoaderProvider.overrideWithValue(loader),
      ],
      child: const MaterialApp(
        home: ApprovalRequestPage(
          applicationKey: 'attendance.leave',
          templateId: '1',
          initialFormData: {'reason': _reason},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(
    tester.element(find.byType(ApprovalRequestPage)),
  );
  container
      .read(oaSyncAvailabilityControllerProvider.notifier)
      .markUnavailable();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
  return container;
}

void main() {
  for (final status in [null, 503, 400, 401, 409, 422, -1]) {
    testWidgets(
      'preview recovery classifies failure $status and retains values',
      (tester) async {
        var calls = 0;
        final forms = <Map<String, Object?>>[];
        final container = await _open(tester, ({
          required String applicationKey,
          required OaApprovalTemplate template,
          required Map<String, Object?> formData,
        }) async {
          calls++;
          forms.add(formData);
          if (calls == 1) {
            throw _failure(
              status == -1 ? null : status,
              cancelled: status == -1,
            );
          }
          return PreviewData.workflowPreview(template);
        });
        expect(calls, 1);
        container
            .read(oaSyncAvailabilityControllerProvider.notifier)
            .markAvailable();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();
        final retries = status == null || status == 503;
        expect(calls, retries ? 2 : 1);
        expect(forms.every((value) => value['reason'] == _reason), isTrue);
        if (retries) {
          expect(find.text('审批流程暂时无法同步，表单与草稿已保留'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'preview recovery does not lose recovery during an in-flight failure',
    (tester) async {
      var calls = 0;
      final first = Completer<OaWorkflowPreview>();
      final container = await _open(tester, ({
        required String applicationKey,
        required OaApprovalTemplate template,
        required Map<String, Object?> formData,
      }) {
        calls++;
        return calls == 1
            ? first.future
            : Future.value(PreviewData.workflowPreview(template));
      });
      final availability = container.read(
        oaSyncAvailabilityControllerProvider.notifier,
      );
      availability.markAvailable();
      await tester.pump();
      expect(calls, 1);
      first.completeError(TimeoutException('test-only timeout'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('审批流程暂时无法同步，表单与草稿已保留'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'preview recovery retries only once per recovery and keeps manual retry',
    (tester) async {
      var calls = 0;
      final container = await _open(tester, ({
        required String applicationKey,
        required OaApprovalTemplate template,
        required Map<String, Object?> formData,
      }) async {
        calls++;
        if (calls < 3) throw _failure(503);
        return PreviewData.workflowPreview(template);
      });
      final availability = container.read(
        oaSyncAvailabilityControllerProvider.notifier,
      );
      availability.markAvailable();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(calls, 2);
      availability.markAvailable();
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(calls, 2);
      final retry = find.byTooltip('重新解析审批流程');
      await tester.ensureVisible(retry);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(calls, 3);
      expect(find.text('审批流程暂时无法同步，表单与草稿已保留'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('preview recovery cancels scheduled retry when the page closes', (
    tester,
  ) async {
    var calls = 0;
    final container = await _open(tester, ({
      required String applicationKey,
      required OaApprovalTemplate template,
      required Map<String, Object?> formData,
    }) async {
      calls++;
      throw _failure(null);
    });
    container
        .read(oaSyncAvailabilityControllerProvider.notifier)
        .markAvailable();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
}
