import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:hexing_terminal_mobile/core/demo/preview_data.dart';
import 'package:hexing_terminal_mobile/features/collaboration/data/collaboration_repositories.dart';
import 'package:hexing_terminal_mobile/features/collaboration/domain/collaboration_models.dart';
import 'package:hexing_terminal_mobile/features/todos/presentation/approval_detail_page.dart';

void main() {
  for (final sample in [
    (code: 'add_signed', actor: '测试审批人', comment: 'AI-UAT-BEFORE'),
    (code: 'ADD_SIGNED', actor: '测试审批人', comment: 'AI-UAT-AFTER'),
    (code: 'add_sign', actor: '测试审批人', comment: 'AI-UAT-LEGACY'),
    (code: 'add_signed', actor: '', comment: ''),
  ]) {
    testWidgets(
      'approval history translates ${sample.code} with actor=${sample.actor}',
      (tester) async {
        tester.view.physicalSize = const Size(360, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final source = PreviewData.oaBootstrap.approvalRequests.first;
        final request = OaApprovalRequest(
          id: 'history-label-fixture',
          requesterId: source.requesterId,
          title: '加签历史',
          formDataJson: '{}',
          formSchemaSnapshotJson: '{}',
          status: 'submitted',
          createdAt: source.createdAt,
          updatedAt: source.updatedAt,
          requesterName: source.requesterName,
          requesterDepartmentName: source.requesterDepartmentName,
          templateName: source.templateName,
          templateCategory: source.templateCategory,
          allowedActions: const [],
          tasks: const [],
          actions: [
            OaApprovalAction.fromJson({
              'action': sample.code,
              'actorName': sample.actor,
              'comment': sample.comment,
              'occurredAt': '2026-09-02T18:22:47Z',
            }),
          ],
          attachments: const [],
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              approvalDetailAutoRefreshProvider.overrideWithValue(false),
              oaSyncAvailabilityProvider.overrideWithValue(
                OaSyncAvailability.available,
              ),
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
              home: ApprovalDetailPage(approvalId: request.id),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final expected = [
          '加签',
          if (sample.comment.isNotEmpty) sample.comment,
        ].join(' · ');
        expect(find.text(expected), findsOneWidget);
        expect(find.textContaining(sample.code), findsNothing);
        expect(
          find.text(sample.actor.isEmpty ? '系统' : sample.actor),
          findsOneWidget,
        );
        expect(
          find.text(
            DateFormat('MM-dd HH:mm')
                .format(request.actions.single.occurredAt!),
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
