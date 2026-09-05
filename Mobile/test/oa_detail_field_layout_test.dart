import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/todos/presentation/approval_detail_page.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 1.6]) {
      testWidgets('detail labels preserve words at width=$width scale=$scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 1100);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        const labels = ['开始时间', '加班时长（小时）', '跨部门结算费用与附加说明', '加班事由'];
        final source = PreviewData.oaBootstrap.approvalRequests.first;
        final request = OaApprovalRequest(
          id: 'label-layout',
          requesterId: source.requesterId,
          title: '加班审批',
          formDataJson: jsonEncode({
            '0': '2026-09-03 16:04',
            '1': '1.0',
            '2': '测试说明',
            '3': 'AI-UAT-20260902-230500-OVERTIME-SESSION',
          }),
          formSchemaSnapshotJson: jsonEncode({
            'fields': [
              for (var i = 0; i < labels.length; i++)
                {
                  'id': '$i',
                  'label': labels[i],
                  'type': i == 3 ? 'textarea' : 'text',
                },
            ],
          }),
          status: 'approved',
          createdAt: source.createdAt,
          updatedAt: source.updatedAt,
          requesterName: source.requesterName,
          requesterDepartmentName: source.requesterDepartmentName,
          templateName: source.templateName,
          templateCategory: source.templateCategory,
          allowedActions: const [],
          tasks: const [],
          actions: const [],
          attachments: const [],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              approvalDetailAutoRefreshProvider.overrideWithValue(false),
              oaApprovalRequestProvider(request.id)
                  .overrideWith((ref) async => request),
              oaBootstrapProvider.overrideWith(
                (ref) async => PreviewData.oaBootstrap,
              ),
              oaApplicationCatalogProvider.overrideWith(
                (ref) async => PreviewData.oaCatalog,
              ),
              imBootstrapProvider.overrideWith(
                (ref) async => PreviewData.imBootstrap,
              ),
            ],
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: ApprovalDetailPage(approvalId: request.id),
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final label in labels) {
          final finder = find.text(label);
          final valueFinder = find.byKey(
            ValueKey('approval-detail-value-$label'),
          );
          final labelRect = tester.getRect(finder);
          final valueRect = tester.getRect(valueFinder);
          // Labels either fit one intact line beside the value or use the full
          // row above it. No multi-line label squeezed against a single value.
          final stacked = valueRect.top >= labelRect.bottom;
          if (!stacked) expect(labelRect.height, lessThan(13 * scale * 1.6));
          if (label == labels[2]) expect(stacked, isTrue);
          if (label == labels[3]) {
            expect(
              find.ancestor(of: valueFinder, matching: find.byType(FittedBox)),
              findsNothing,
            );
            expect(tester.widget<Text>(valueFinder).softWrap, isTrue);
            expect(tester.widget<Text>(valueFinder).maxLines, isNull);
          }
          expect(
            tester.widget<Text>(finder).overflow,
            isNot(TextOverflow.ellipsis),
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }
}
